"use strict";

// Moving start preserves the marker duration. Newly created markers are points.
module.exports = function markerBounds(marker, start, end = start, timeEnd = false) {
    const seconds = value => typeof value === "number" ? value : value.seconds;
    Object.defineProperties(marker, {
        start: {
            enumerable: true, configurable: true,
            get() { return { seconds: start }; },
            set(value) {
                const duration = end - start;
                start = seconds(value);
                end = start + duration;
            }
        },
        end: {
            enumerable: true, configurable: true,
            get() { return timeEnd ? { seconds: end } : end; },
            set(value) { end = seconds(value); }
        }
    });
    return marker;
};
