#import "BodyTests-Bridging-Header.h"

HKWorkout *BodyTestMakeWorkout(HKWorkoutActivityType activityType,
                               NSDate *start,
                               NSDate *end,
                               NSDictionary<NSString *, id> *metadata) {
    // HKWorkoutBuilder.finishWorkout creates AND saves a workout. Tests need a
    // real HKWorkout object without permissions, healthd, or database writes.
    // Keep this exception confined to the public in-memory factory; deprecation
    // warnings remain enabled everywhere else, including all production code.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [HKWorkout workoutWithActivityType:activityType
                                   startDate:start
                                     endDate:end
                               workoutEvents:nil
                           totalEnergyBurned:nil
                               totalDistance:nil
                                    metadata:metadata];
#pragma clang diagnostic pop
}
