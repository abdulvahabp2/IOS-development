//
//  googleOAuth.m
//  salesToolApp
//
//  Created by abdul on 4/7/15.
//  Copyright (c) 2015 Position2. All rights reserved.
//

#import "googleOAuth.h"

@implementation googleOAuth
// The Client ID from the Google Developer Console .

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect {
    // Drawing code
}
*/


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Set the access token and the refresh token file paths.
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *docDirectory = [paths objectAtIndex:0];
        _accessTokenInfoFile = [[NSString alloc] initWithFormat:@"%@/acctok", docDirectory];
        _refreshTokenFile = [[NSString alloc] initWithFormat:@"%@/reftok", docDirectory];
        
        // Set the redirect URI.
        // This is taken from the Google Developers Console.
        _redirectUri = @"urn:ietf:wg:oauth:2.0:oob";
        
        // Make any other required initializations.
        _receivedData = [[NSMutableData alloc] init];
        _urlConnection = [[NSURLConnection alloc] init];
        _refreshToken = nil;
        _isRefreshing = NO;
    }
    return self;
}

-(void)authorizeUserWithClientID:(NSString *)client_ID andCleintSecret:(NSString *)client_Secret andParentView:(UIView *)parent_view andScopes:(NSArray *)scopes{
    
    // store into the local private properties all the parameter
    
    _clientID        = [[NSString alloc] initWithString:client_ID];
    _clientSecret    = [[NSString alloc] initWithString:client_Secret];
    _scopes          = [[NSMutableArray alloc] initWithArray:scopes copyItems:YES];
    _parentView      = parent_view;
    
    
    // Check if the access token info file exists or not.
    if ([self checkIfAccessTokenInfoFileExists]) {
        // In case it exists load the access token info and check if the access token is valid.
        [self loadAccessTokenInfo];
        if ([self checkIfShouldRefreshAccessToken]) {
            // If the access token is not valid then refresh it.
            [self refreshAccessToken];
        }
        else{
            // Otherwise tell the caller through the delegate class that the authorization is successful.
            [self.gOAuthDelegate authorizationWasSuccessful];
        }
        
    }
    else{
        // In case that the access token info file is not found then show the
        // webview to let user sign in and allow access to the app.
        [self showWebviewForUserLogin];
    }
}

-(void)showWebviewForUserLogin{
    
    NSString *scope=@"";
    for(int i = 0 ; i < [_scopes count]; i++){
        scope = [scope stringByAppendingString:[self urlEncodeString:[_scopes objectAtIndex:i]]];
   
        if(1 < [_scopes count] - 1){
            scope = [scope stringByAppendingString:@"+"];
        }
    }
    // Form the URL string.
    NSString *targetURLString = [NSString stringWithFormat:@"%@?scope=%@&amp;redirect_uri=%@&amp;client_id=%@&amp;response_type=code",
                                 authorizationTokenEndpoint,
                                 scope,
                                 _redirectUri,
                                 _clientID];
    // Do some basic webview setup.
    [self setDelegate:self];
    [self setScalesPageToFit:YES];
    [self setAutoresizingMask:_parentView.autoresizingMask];
    
    // Make the request and add self (webview) to the parent view.
    [self loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:targetURLString]]];
    [_parentView addSubview:self];
    
}

-(void)webViewDidFinishLoad:(UIWebView *)webView{
    // Get the webpage title.
    NSString *webviewTitle = [webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    //NSLog(@"Webview Title = %@", webviewTitle);
    
    // Check for the "Success token" literal in title.
    if ([webviewTitle rangeOfString:@"Success code"].location != NSNotFound) {
        // The oauth code has been retrieved.
        // Break the title based on the equal sign (=).
        NSArray *titleParts = [webviewTitle componentsSeparatedByString:@"="];
        // The second part is the oauth token.
        _authorizationCode = [[NSString alloc] initWithString:[titleParts objectAtIndex:1]];
        
        // Show a "Please wait..." message to the webview.
        NSString *html = @"<html><head><title>Please wait</title></head><body><h1>Please wait...</h1></body></html>";
        [self loadHTMLString:html baseURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]]];
        
        // Exchange the authorization code for an access code.
        [self exchangeAuthorizationCodeForAccessToken];
    }
    else{
        if ([webviewTitle rangeOfString:@"access_denied"].location != NSNotFound) {
            // In case that the user tapped on the Cancel button instead of the Accept, then just
            // remove the webview from the superview.
            [webView removeFromSuperview];
        }
    }
}

-(void)exchangeAuthorizationCodeForAccessToken{
    // Create a string containing all the post parameters required to exchange the authorization code
    // with the access token.
    NSString *postParams = [NSString stringWithFormat:@"code=%@&amp;client_id=%@&amp;client_secret=%@&amp;redirect_uri=%@&amp;grant_type=authorization_code",
                            _authorizationCode,
                            _clientID,
                            _clientSecret,
                            _redirectUri];
    
    // Create a mutable request object and set its properties.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:accessTokenEndpoint]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[postParams dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    // Make the request.
    [self makeRequest:request];
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error{
    
    [self.gOAuthDelegate errorOccuredWithShortDescription:@"Connection failed." andErrorDetails:[error localizedDescription]];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection{
    // This object will be used to store the converted received JSON data to string.
    NSString *responseJSON;
    
    // This flag indicates whether the response was received after an API call and out of the
    // following cases.
    BOOL isAPIResponse = YES;
    
    // Convert the received data in NSString format.
    responseJSON = [[NSString alloc] initWithData:(NSData *)_receivedData encoding:NSUTF8StringEncoding];
    
    if ([responseJSON rangeOfString:@"invalid_request"].location != NSNotFound) {
        NSLog(@"General error occured.");
        
        // If a refresh was on the way then set the respective flag to NO.
        if (_isRefreshing) {
            _isRefreshing = NO;
        }
        
        // Notify the caller class through the delegate.
        [self.gOAuthDelegate errorInResponseWithBody:responseJSON];
        
        
        isAPIResponse = NO;
    }
    
    
    // Check for invalid refresh token.
    // In that case guide the user to enter the credentials again.
    if ([responseJSON rangeOfString:@"invalid_grant"].location != NSNotFound) {
        if (_isRefreshing) {
            _isRefreshing = NO;
        }
        
        [self showWebviewForUserLogin];
        
        isAPIResponse = NO;
    }
    
    
    if ([responseJSON rangeOfString:@"invalid_request"].location != NSNotFound) {
        NSLog(@"General error occured.");
        
        // If a refresh was on the way then set the respective flag to NO.
        if (_isRefreshing) {
            _isRefreshing = NO;
        }
        
        // Notify the caller class through the delegate.
        [self.gOAuthDelegate errorInResponseWithBody:responseJSON];
        
        
        isAPIResponse = NO;
    }
    
    // Check for access token.
    if ([responseJSON rangeOfString:@"access_token"].location != NSNotFound) {
        // This is the case where the access token has been fetched.
        [self storeAccessTokenInfo];
        
        // Remove the webview from the superview.
        [self removeFromSuperview];
        
        if (_isRefreshing) {
            _isRefreshing = NO;
        }
        
        // Notify the caller class that the authorization was successful.
        [self.gOAuthDelegate authorizationWasSuccessful];
        
        isAPIResponse = NO;
    }
}

-(void)refreshAccessToken{
    // Load the refrest token if it's not loaded alredy.
    if (_refreshToken == nil) {
        [self loadRefreshToken];
    }
    
    // Set the HTTP POST parameters required for refreshing the access token.
    NSString *refreshPostParams = [NSString stringWithFormat:@"refresh_token=%@&client_id=%@&client_secret=%@&grant_type=refresh_token",
                                   _refreshToken,
                                   _clientID,
                                   _clientSecret
                                   ];
    
    // Indicate that an access token refresh process is on the way.
    _isRefreshing = YES;
    
    // Create the request object and set its properties.
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:accessTokenEndpoint]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[refreshPostParams dataUsingEncoding:NSUTF8StringEncoding]];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    
    // Make the request.
    [self makeRequest:request];
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data{
    // Append any new data to the _receivedData object.
    [_receivedData appendData:data];
}

-(NSString *)urlEncodeString:(NSString *)stringToURLEncode{
    // URL-encode the parameter string and return it.
    CFStringRef encodedURL = CFURLCreateStringByAddingPercentEscapes(NULL,
                                                                     (CFStringRef) stringToURLEncode,
                                                                     NULL,
                                                                     (CFStringRef)@"!@#$%&*'();:=+,/?[]",
                                                                     kCFStringEncodingUTF8);
    return (NSString *)CFBridgingRelease(encodedURL);
}

-(void)storeAccessTokenInfo{
    
    NSError *error;
    // Keep the access token info into a dictionary.
    _accessTokenInfoDictionary = [NSJSONSerialization JSONObjectWithData:_receivedData options:NSJSONReadingMutableContainers error:&error];
    // Check if any error occured while converting NSData data to NSDictionary.
    if (error) {
        [self.gOAuthDelegate errorOccuredWithShortDescription:@"An error occured while saving access token info into a NSDictionary."
                                              andErrorDetails:[error localizedDescription]];
    }
    // Save the dictionary to a file.
    [_accessTokenInfoDictionary writeToFile:_accessTokenInfoFile atomically:YES];
    // If a refresh token is found inside the access token info dictionary then save it separately.
    if ([_accessTokenInfoDictionary objectForKey:@"refresh_token"] != nil) {
        // Extract the refresh token.
        _refreshToken = [[NSString alloc] initWithString:[_accessTokenInfoDictionary objectForKey:@"refresh_token"]];
        
        // Save the refresh token as data.
        [_refreshToken writeToFile:_refreshTokenFile atomically:YES encoding:NSUTF8StringEncoding error:&error];
        
        // If an error occurs while saving the refresh token notify the caller class.
        if (error) {
            [self.gOAuthDelegate errorOccuredWithShortDescription:@"An error occured while saving the refresh token."
                                                  andErrorDetails:[error localizedDescription]];
        }
    }
    
}

-(void)loadAccessTokenInfo{
    // check if the access token file exits
    if ([self checkIfAccessTokenInfoFileExists]) {
        // Load the access token info from the file into the dictionary.
        _accessTokenInfoDictionary = [[NSMutableDictionary alloc] initWithContentsOfFile:_accessTokenInfoFile];
    }
    else{
        // If the access token info file doesn't exist then inform the caller class through the delegate.
        [self.gOAuthDelegate errorOccuredWithShortDescription:@"Access token info file was not found." andErrorDetails:@""];
    }
    
}

-(void)loadRefreshToken{
    // Check if the refresh token file exists.
    if ([self checkIfRefreshTokenFileExists]) {
        NSError *error;
        _refreshToken = [[NSString alloc] initWithContentsOfFile:_refreshTokenFile encoding:NSUTF8StringEncoding error:&error];
        
        // If an error occurs while saving the refresh token notify the caller class.
        if (error) {
            [self.gOAuthDelegate errorOccuredWithShortDescription:@"An error occured while loading the refresh token."
                                                  andErrorDetails:[error localizedDescription]];
        }
    }
}

-(BOOL)checkIfAccessTokenInfoFileExists {
    // If the access token info file exists, return YES, otherwise return NO.
    return (![[NSFileManager defaultManager] fileExistsAtPath:_accessTokenInfoFile]) ? NO : YES;
}


-(BOOL)checkIfRefreshTokenFileExists {
    // If the refresh token file exists then return YES, otherwise return NO.
    return (![[NSFileManager defaultManager] fileExistsAtPath:_refreshTokenFile]) ? NO : YES;
}

-(BOOL)checkIfShouldRefreshAccessToken{
    NSError *error = nil;
    
    // Get the time-to-live (in seconds) value regarding the access token.
    int accessTokenTTL = [[_accessTokenInfoDictionary objectForKey:@"expires_in"] intValue];
    // Get the date that the access token file was created.
    NSDate *accessTokenInfoFileCreated = [[[NSFileManager defaultManager] attributesOfItemAtPath:_accessTokenInfoFile error:&error]
                                          fileCreationDate];
    
    // Check if any error occured.
    if (error != nil) {
        [self.gOAuthDelegate errorOccuredWithShortDescription:@"Cannot read access token file's creation date."
                                              andErrorDetails:[error localizedDescription]];
        
        return YES;
    }
    else{
        // Get the time difference between the file creation date and now.
        NSTimeInterval interval = [[NSDate date] timeIntervalSinceDate:accessTokenInfoFileCreated];
        
        // Check if the interval value is equal or greater than the accessTokenTTL value.
        // If that's the case then the access token should be refreshed.
        if (interval >= accessTokenTTL) {
            // In this case the access token should be refreshed.
            return YES;
        }
        else{
            // Otherwise the access token is valid.
            return NO;
        }
    }
}


-(void)makeRequest:(NSMutableURLRequest *)request{
    // Set the length of the _receivedData mutableData object to zero.
    [_receivedData setLength:0];
    
    // Make the request.
    _urlConnection = [NSURLConnection connectionWithRequest:request delegate:self];
}
@end
