//
//  BRUserDefaultsSwitchCell.h
//  BreadWallet
//
//  Created by Samuel Sutch on 12/29/15.
//  Copyright © 2015 Aaron Voisine. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface BRUserDefaultsSwitchCell : UITableViewCell

@property (nonatomic, weak) IBOutlet UISwitch *theSwitch;
@property (nonatomic, weak) IBOutlet UILabel *titleLabel;
- (IBAction)didUpdateSwitch:(id)sender;
- (void)setUserDefaultsKey:(NSString *)key;

@end
