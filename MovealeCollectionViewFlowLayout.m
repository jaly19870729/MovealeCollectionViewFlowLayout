//
//  MovealeCollectionViewFlowLayout.m
//
//  Created by jaly19870729 on 17/2/24.
//  Copyright © 2017年 jaly19870729. All rights reserved.
//

#import "MovealeCollectionViewFlowLayout.h"
#import <objc/runtime.h>

#ifndef CGGEOMETRY_LXSUPPORT_H_
CG_INLINE CGPoint
MT_CGPointAdd(CGPoint point1, CGPoint point2) {
    return CGPointMake(point1.x + point2.x, point1.y + point2.y);
}
#endif


typedef NS_ENUM(NSInteger, MTScrollingDirection) {
    MTScrollingDirectionUnknown = 0,
    MTScrollingDirectionUp,
    MTScrollingDirectionDown,
    MTScrollingDirectionLeft,
    MTScrollingDirectionRight
};


static NSString * const kMTScrollingDirectionKey = @"MTScrollingDirection";

@interface CADisplayLink (MT_userInfo)
@property (nonatomic, copy) NSDictionary *MT_userInfo;
@end

@implementation CADisplayLink (MT_userInfo)
- (void) setMT_userInfo:(NSDictionary *) MT_userInfo {
    objc_setAssociatedObject(self, "MT_userInfo", MT_userInfo, OBJC_ASSOCIATION_COPY);
}

- (NSDictionary *) MT_userInfo {
    return objc_getAssociatedObject(self, "MT_userInfo");
}
@end

@interface UICollectionViewCell (Snapshot)

- (UIView *)MT_snapshotView;

@end

@implementation UICollectionViewCell (Snapshot)

- (UIView *)MT_snapshotView {
    if ([self respondsToSelector:@selector(snapshotViewAfterScreenUpdates:)]) {
        return [self snapshotViewAfterScreenUpdates:YES];
    } else {
        UIGraphicsBeginImageContextWithOptions(self.bounds.size, self.isOpaque, 0.0f);
        [self.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return [[UIImageView alloc] initWithImage:image];
    }
}

@end

@interface MovealeCollectionViewFlowLayout ()

@property(strong, nonatomic)UILongPressGestureRecognizer *longGestureRecognizer;
@property(strong, nonatomic)NSIndexPath *selectedMoveIndexPath;
@property(strong, nonatomic)UIView *currentMoveView;
@property (assign, nonatomic) CGPoint currentPoint;
@property (assign, nonatomic) CGPoint startPoint;
@property (assign, nonatomic) CGPoint currentViewCenter;

@property (assign, nonatomic) CGFloat scrollingSpeed;
@property (assign, nonatomic) UIEdgeInsets scrollingTriggerEdgeInsets;
@property (strong, nonatomic) CADisplayLink *displayLink;


@end

@interface MovealeCollectionViewFlowLayout (LongPress)<UIGestureRecognizerDelegate>

@end

@implementation MovealeCollectionViewFlowLayout

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self setScrollDefaults];
        [self addCollectionCreatedObserver];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setScrollDefaults];
        [self addCollectionCreatedObserver];
    }
    return self;
}

-(void)addCollectionCreatedObserver{
    [self addObserver:self forKeyPath:@"collectionView" options:NSKeyValueObservingOptionNew context:nil];
}

-(void)removeCollectionObserver{
    [self removeObserver:self forKeyPath:@"collection"];
}

- (void)setScrollDefaults {
    _scrollingSpeed = 300.0f;
    _scrollingTriggerEdgeInsets = UIEdgeInsetsMake(50.0f, 50.0f, 50.0f, 50.0f);
}

-(void)dealloc{
    [self removeCollectionObserver];
    [self tearDownCollectionView];
}

- (void)setupScrollTimerInDirection:(MTScrollingDirection)direction {
    if (!self.displayLink.paused) {
        MTScrollingDirection oldDirection = [self.displayLink.MT_userInfo[kMTScrollingDirectionKey] integerValue];
        
        if (direction == oldDirection) {
            return;
        }
    }
    
    [self invalidatesScrollTimer];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleScroll:)];
    self.displayLink.MT_userInfo = @{ kMTScrollingDirectionKey : @(direction) };
    
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

// Tight loop, allocate memory sparely, even if they are stack allocation.
- (void)handleScroll:(CADisplayLink *)displayLink {
    MTScrollingDirection direction = (MTScrollingDirection)[displayLink.MT_userInfo[kMTScrollingDirectionKey] integerValue];
    if (direction == MTScrollingDirectionUnknown) {
        return;
    }
    
    CGSize frameSize = self.collectionView.bounds.size;
    CGSize contentSize = self.collectionView.contentSize;
    CGPoint contentOffset = self.collectionView.contentOffset;
    UIEdgeInsets contentInset = self.collectionView.contentInset;
    // Important to have an integer `distance` as the `contentOffset` property automatically gets rounded
    // and it would diverge from the view's center resulting in a "cell is slipping away under finger"-bug.
    CGFloat distance = rint(self.scrollingSpeed * displayLink.duration);
    CGPoint translation = CGPointZero;
    
    switch(direction) {
        case MTScrollingDirectionUp: {
            distance = -distance;
            CGFloat minY = 0.0f - contentInset.top;
            
            if ((contentOffset.y + distance) <= minY) {
                distance = -contentOffset.y - contentInset.top;
            }
            
            translation = CGPointMake(0.0f, distance);
        } break;
        case MTScrollingDirectionDown: {
            CGFloat maxY = MAX(contentSize.height, frameSize.height) - frameSize.height + contentInset.bottom;
            
            if ((contentOffset.y + distance) >= maxY) {
                distance = maxY - contentOffset.y;
            }
            
            translation = CGPointMake(0.0f, distance);
        } break;
        case MTScrollingDirectionLeft: {
            distance = -distance;
            CGFloat minX = 0.0f - contentInset.left;
            
            if ((contentOffset.x + distance) <= minX) {
                distance = -contentOffset.x - contentInset.left;
            }
            
            translation = CGPointMake(distance, 0.0f);
        } break;
        case MTScrollingDirectionRight: {
            CGFloat maxX = MAX(contentSize.width, frameSize.width) - frameSize.width + contentInset.right;
            
            if ((contentOffset.x + distance) >= maxX) {
                distance = maxX - contentOffset.x;
            }
            
            translation = CGPointMake(distance, 0.0f);
        } break;
        default: {
            // Do nothing...
        } break;
    }
    self.collectionView.contentOffset = MT_CGPointAdd(contentOffset, translation);
}

#pragma mark - Observer 

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context{
    if([keyPath isEqualToString:@"collectionView"]){
        if(self.collectionView){
            [self setupCollectionView];
        }else{
            [self tearDownCollectionView];
        }
    }
}

#pragma mark -

- (void)invalidatesScrollTimer {
    if (!self.displayLink.paused) {
        [self.displayLink invalidate];
    }
    self.displayLink = nil;
}

-(void)tearDownCollectionView{
    if(self.longGestureRecognizer){
        UIView *view = self.longGestureRecognizer.view;
        if(view){
            [view removeGestureRecognizer:self.longGestureRecognizer];
        }
        self.longGestureRecognizer.delegate = nil;
        self.longGestureRecognizer = nil;
    }
}

-(void)setupCollectionView{
    self.longGestureRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handlerLongPressGesture:)];
    self.longGestureRecognizer.delegate = self;
    [self.collectionView addGestureRecognizer:self.longGestureRecognizer];
}

#pragma mark - Gesture

-(void)handlerLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer{
    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan:
            [self startLongPressGesture:gestureRecognizer];
            break;
        case UIGestureRecognizerStateChanged:
            [self moveLongPressGesture:gestureRecognizer];
            break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateEnded:
            [self endLongPressGesture:gestureRecognizer];
            break;
        default:
            break;
    }
}

-(void)startLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer{
    NSIndexPath *currentIndexPath = [self.collectionView indexPathForItemAtPoint:[gestureRecognizer locationInView:self.collectionView]];
    if(currentIndexPath == nil){
        return;
    }
    self.startPoint = [gestureRecognizer locationInView:self.collectionView];
    self.selectedMoveIndexPath = currentIndexPath;
    UICollectionViewCell *collectionViewCell = [self.collectionView cellForItemAtIndexPath:self.selectedMoveIndexPath];
    self.currentMoveView = [[UIView alloc] initWithFrame:collectionViewCell.frame];
    collectionViewCell.highlighted = YES;
    
    UIView *highlightedISnapshotView = [collectionViewCell MT_snapshotView];
    highlightedISnapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    highlightedISnapshotView.alpha = 1.0;
    
    collectionViewCell.highlighted = NO;
    UIView *snapshotView = [collectionViewCell MT_snapshotView];
    snapshotView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    snapshotView.alpha = 0.0;
    
    [self.currentMoveView addSubview:snapshotView];
    [self.currentMoveView addSubview:highlightedISnapshotView];
    [self.collectionView addSubview:self.currentMoveView];
    self.currentViewCenter = self.currentMoveView.center;
    //动画
    __weak typeof(self) weakSelf = self;
    [UIView
     animateWithDuration:0.3
     delay:0.0
     options:UIViewAnimationOptionBeginFromCurrentState
     animations:^{
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf) {
             strongSelf.currentMoveView.transform = CGAffineTransformMakeScale(1.1f, 1.1f);
             highlightedISnapshotView.alpha = 0.0f;
             snapshotView.alpha = 1.0f;
         }
     }
     completion:^(BOOL finished) {
         __strong typeof(self) strongSelf = weakSelf;
         if (strongSelf) {
             [highlightedISnapshotView removeFromSuperview];
         }
     }];
    [self invalidateLayout];
}

-(void)moveLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer{
    CGPoint currentPoint = [gestureRecognizer locationInView:self.collectionView];
    self.currentPoint = CGPointMake(currentPoint.x - self.startPoint.x, currentPoint.y - self.startPoint.y);
    CGPoint viewCenter = self.currentMoveView.center = MT_CGPointAdd(self.currentViewCenter, self.currentPoint);
    [self invalidateLayoutIfNecessary];
    switch (self.scrollDirection) {
        case UICollectionViewScrollDirectionVertical: {
            if (viewCenter.y < (CGRectGetMinY(self.collectionView.bounds) + self.scrollingTriggerEdgeInsets.top)) {
                [self setupScrollTimerInDirection:MTScrollingDirectionUp];
            } else {
                if (viewCenter.y > (CGRectGetMaxY(self.collectionView.bounds) - self.scrollingTriggerEdgeInsets.bottom)) {
                    [self setupScrollTimerInDirection:MTScrollingDirectionDown];
                } else {
                    [self invalidatesScrollTimer];
                }
            }
        } break;
        case UICollectionViewScrollDirectionHorizontal: {
            if (viewCenter.x < (CGRectGetMinX(self.collectionView.bounds) + self.scrollingTriggerEdgeInsets.left)) {
                [self setupScrollTimerInDirection:MTScrollingDirectionLeft];
            } else {
                if (viewCenter.x > (CGRectGetMaxX(self.collectionView.bounds) - self.scrollingTriggerEdgeInsets.right)) {
                    [self setupScrollTimerInDirection:MTScrollingDirectionRight];
                } else {
                    [self invalidatesScrollTimer];
                }
            }
        } break;
    }
}

-(void)endLongPressGesture:(UILongPressGestureRecognizer *)gestureRecognizer{
    NSIndexPath *currentIndexPath = self.selectedMoveIndexPath;
    if(currentIndexPath){
        self.selectedMoveIndexPath = nil;
        self.currentViewCenter = CGPointZero;
        UICollectionViewLayoutAttributes *layoutAttributes = [self layoutAttributesForItemAtIndexPath:currentIndexPath];
        
        self.longGestureRecognizer.enabled = NO;
        //动画
        __weak typeof(self) weakSelf = self;
        [UIView
         animateWithDuration:0.3
         delay:0.0
         options:UIViewAnimationOptionBeginFromCurrentState
         animations:^{
             __strong typeof(self) strongSelf = weakSelf;
             if (strongSelf) {
                 strongSelf.currentMoveView.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
                 strongSelf.currentMoveView.center = layoutAttributes.center;
             }
         }
         completion:^(BOOL finished) {
             self.longGestureRecognizer.enabled = YES;
             __strong typeof(self) strongSelf = weakSelf;
             if (strongSelf) {
                 [strongSelf.currentMoveView removeFromSuperview];
                 strongSelf.currentMoveView = nil;
                 [strongSelf invalidateLayout];
             }
         }];
    
    
    }
    [self invalidatesScrollTimer];
}

#pragma mark -

-(void)invalidateLayoutIfNecessary{
    
    NSIndexPath *newIndexPath = [self.collectionView indexPathForItemAtPoint:self.currentMoveView.center];
    NSIndexPath *preIndexPath = self.selectedMoveIndexPath;
    if(newIndexPath == nil || [newIndexPath isEqual:preIndexPath]){
        return;
    }
    if(newIndexPath.section == 1){
        return;
    }
    self.selectedMoveIndexPath = newIndexPath;
    
    if ([self.collectionView.dataSource respondsToSelector:@selector(collectionView:moveItemAtIndexPath:toIndexPath:)]) {
        [self.collectionView.dataSource collectionView:self.collectionView moveItemAtIndexPath:preIndexPath toIndexPath:newIndexPath];
    }
    __weak typeof(self) weakSelf = self;
    [self.collectionView performBatchUpdates:^{
        [weakSelf.collectionView deleteItemsAtIndexPaths:@[preIndexPath]];
        [weakSelf.collectionView insertItemsAtIndexPaths:@[newIndexPath]];
    } completion:^(BOOL finished) {
        
    }];
}

#pragma mark - overridden

-(NSArray *)layoutAttributesForElementsInRect:(CGRect)rect{
    NSArray *layoutAttributesForElementsInRect = [super layoutAttributesForElementsInRect:rect];
    for (UICollectionViewLayoutAttributes *layoutAttributes in layoutAttributesForElementsInRect) {
        if(layoutAttributes.representedElementCategory == UICollectionElementCategoryCell){
            [self applyLayoutAttributes:layoutAttributes];
        }
    }
    return layoutAttributesForElementsInRect;
}

-(UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath{
    UICollectionViewLayoutAttributes *layoutAttributes = [super layoutAttributesForItemAtIndexPath:indexPath];
    if(layoutAttributes.representedElementCategory == UICollectionElementCategoryCell){
        [self applyLayoutAttributes:layoutAttributes];
    }
    return layoutAttributes;
}

-(void)applyLayoutAttributes:(UICollectionViewLayoutAttributes *)layoutAttributes {
    if([layoutAttributes.indexPath isEqual:self.selectedMoveIndexPath]){
        layoutAttributes.hidden = YES;
    }
}


@end

@implementation MovealeCollectionViewFlowLayout (LongPress)



@end
