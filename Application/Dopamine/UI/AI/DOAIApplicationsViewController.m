//
//  DOAIApplicationsViewController.m
//  Dopamine
//
//  Created by GPT-5 Codex on 31/10/2025.
//

#import "DOAIApplicationsViewController.h"
#import "DOPSListController.h"
#import "DOPSListItemsController.h"
#import "DOUIManager.h"

@interface DOAIApplicationsViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;

@end

@implementation DOAIApplicationsViewController

- (instancetype)init
{
    self = [super init];
    if (self) {
        _sections = [self buildSections];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [DOPSListController setupViewControllerStyle:self];

    UIView *header = [DOPSListItemsController makeHeader:DOLocalizedString(@"AI_Applications_Header") withTarget:self];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:header];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:5],
        [header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:70]
    ]];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.tableView.showsVerticalScrollIndicator = NO;
    self.tableView.estimatedRowHeight = 72;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.contentInset = UIEdgeInsetsMake(12, 0, 24, 0);

    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:-6],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-12]
    ]];
}

#pragma mark - Table View Data

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSArray *items = self.sections[section][@"items"];
    return (NSInteger)items.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return self.sections[section][@"title"];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 38.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UILabel *label = [[UILabel alloc] init];
    label.text = self.sections[section][@"title"];
    label.textColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];

    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor clearColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:4],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-4],
        [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-6]
    ]];

    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 10.0;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section
{
    UIView *view = [[UIView alloc] init];
    view.backgroundColor = [UIColor clearColor];
    return view;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"AIAppCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
        cell.backgroundColor = [UIColor clearColor];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

        UIView *background = [[UIView alloc] initWithFrame:CGRectZero];
        background.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        background.layer.cornerRadius = 14;
        background.layer.masksToBounds = YES;
        background.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:background];
        [cell.contentView sendSubviewToBack:background];

        [NSLayoutConstraint activateConstraints:@[
            [background.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [background.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [background.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:4],
            [background.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4]
        ]];

        UIView *selectedBackground = [[UIView alloc] initWithFrame:CGRectZero];
        selectedBackground.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        selectedBackground.layer.cornerRadius = 14;
        selectedBackground.layer.masksToBounds = YES;
        cell.selectedBackgroundView = selectedBackground;

        UILabel *titleLabel = cell.textLabel;
        titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        titleLabel.textColor = [UIColor whiteColor];

        UILabel *subtitleLabel = cell.detailTextLabel;
        subtitleLabel.font = [UIFont systemFontOfSize:13];
        subtitleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
        subtitleLabel.numberOfLines = 0;
    }

    NSDictionary *entry = [self itemAtIndexPath:indexPath];
    cell.textLabel.text = entry[@"name"];
    cell.detailTextLabel.text = entry[@"description"];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    cell.contentView.backgroundColor = [UIColor clearColor];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *entry = [self itemAtIndexPath:indexPath];
    NSString *urlString = entry[@"url"];
    if (!urlString.length) {
        return;
    }
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    });
}

#pragma mark - Helpers

- (NSArray<NSDictionary *> *)buildSections
{
    return @[
        @{
            @"title": DOLocalizedString(@"AI_Section_Chatbots"),
            @"items": @[
                @{@"name": @"ChatGPT", @"description": @"General-purpose assistant for ideation, explanations, and coding support.", @"url": @"https://chat.openai.com"},
                @{@"name": @"Claude", @"description": @"Anthropic's assistant focused on reasoning-heavy writing and analysis.", @"url": @"https://claude.ai"},
                @{@"name": @"Gemini", @"description": @"Google's multimodal AI with deep search and collaboration features.", @"url": @"https://gemini.google.com"},
                @{@"name": @"Perplexity", @"description": @"Conversational research engine with citation-backed answers.", @"url": @"https://www.perplexity.ai"}
            ]
        },
        @{
            @"title": DOLocalizedString(@"AI_Section_Creative"),
            @"items": @[
                @{@"name": @"Midjourney", @"description": @"Community-driven image generation for concept art and branding.", @"url": @"https://www.midjourney.com"},
                @{@"name": @"Runway", @"description": @"Video editing and generative video tools for storytellers.", @"url": @"https://runwayml.com"},
                @{@"name": @"Ideogram", @"description": @"Text-accurate image generation for marketing and typography designs.", @"url": @"https://ideogram.ai"},
                @{@"name": @"ElevenLabs", @"description": @"High-quality synthetic voices for narration and localization.", @"url": @"https://elevenlabs.io"}
            ]
        },
        @{
            @"title": DOLocalizedString(@"AI_Section_Productivity"),
            @"items": @[
                @{@"name": @"GitHub Copilot", @"description": @"AI pair-programmer that suggests code in real time inside editors.", @"url": @"https://github.com/features/copilot"},
                @{@"name": @"Notion AI", @"description": @"Embedded writing and research assistant within workspace documents.", @"url": @"https://www.notion.so/product/ai"},
                @{@"name": @"Zapier Central", @"description": @"AI-assisted workflow builder that joins apps and automations.", @"url": @"https://zapier.com/ai"},
                @{@"name": @"Cody", @"description": @"Sourcegraph's contextual enterprise AI assistant for codebases.", @"url": @"https://about.sourcegraph.com/cody"}
            ]
        }
    ];
}

- (NSDictionary *)itemAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *items = self.sections[indexPath.section][@"items"];
    return items[indexPath.row];
}

- (void)dismiss
{
    [self.navigationController popViewControllerAnimated:YES];
}

@end
