#import <HealthKit/HealthKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Creates an unsaved workout for FakeHealthStore. Never accesses the HealthKit database.
HKWorkout *BodyTestMakeWorkout(HKWorkoutActivityType activityType,
                               NSDate *start,
                               NSDate *end,
                               NSDictionary<NSString *, id> * _Nullable metadata)
    NS_SWIFT_NAME(makeTestWorkout(activityType:start:end:metadata:));

NS_ASSUME_NONNULL_END
