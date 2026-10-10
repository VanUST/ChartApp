// PURPOSE: Publish the spike harness's surface from one import, so the executable and any later
//          test or CI step drive the same entry point instead of reaching into src/.
// INPUTS: None.
// OUTPUTS: The spike result types and the runnable spikes.
// KEYWORDS: barrel, public-api, spike-harness
library;

export 'src/spike_s3.dart';
export 'src/spike_s4.dart';
