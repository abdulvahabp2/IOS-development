//
//  ViewController.h
//  salesToolApp
//
//  Created by abdul on 4/7/15.
//  Copyright (c) 2015 Position2. All rights reserved.
//

#import <UIKit/UIKit.h> 
#import "GoogleOAuth.h"


@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, GoogleOAuthDelegate>

@property (nonatomic, strong) NSMutableArray *arrProfileInfo;
@property (nonatomic, strong) NSMutableArray *arrProfileInfoLabel;
@property (nonatomic, strong) GoogleOAuth *googleOAuth;
@property (weak, nonatomic) IBOutlet UITableView *table;

- (IBAction)showProfile:(id)sender;

- (IBAction)revokeAccess:(id)sender;
@end

