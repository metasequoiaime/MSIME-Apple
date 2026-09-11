#pragma once
#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>

@protocol MetasequoiaCandidatePanelDelegate <NSObject>
- (void)candidateSelected:(NSAttributedString *)candidate;
- (void)candidatePanelPreviousPage;
- (void)candidatePanelNextPage;
@end

// Nonactivating AppKit presentation of one controller-owned candidate page.
@interface MetasequoiaCandidatePanel : NSObject
@property(nonatomic, weak) id<MetasequoiaCandidatePanelDelegate> delegate;
@property(nonatomic) IMKCandidatePanelType panelType;
@property(nonatomic, copy) NSArray<NSNumber *> *selectionKeys;
@property(nonatomic) NSRect caretRect;
@property(nonatomic) BOOL hasPreviousPage;
@property(nonatomic) BOOL hasNextPage;
@property(nonatomic, readonly) NSPanel *window;
- (void)setAttributes:(NSDictionary *)attributes;
- (void)setCandidateData:(NSArray<NSAttributedString *> *)candidates;
- (void)show:(IMKCandidatesLocationHint)hint;
- (void)hide;
- (BOOL)isVisible;
- (NSRect)candidateFrame;
- (NSInteger)candidateIdentifierAtLineNumber:(NSInteger)line;
- (NSInteger)lineNumberForCandidateWithIdentifier:(NSInteger)identifier;
- (NSInteger)candidateStringIdentifier:(NSAttributedString *)candidate;
- (BOOL)selectCandidateWithIdentifier:(NSInteger)identifier;
- (NSInteger)selectedCandidate;
- (NSAttributedString *)selectedCandidateString;
@end
