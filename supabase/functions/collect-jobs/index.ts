import {scheduledHandler} from '../_shared/edge-jobs-handler.js';

Deno.serve(scheduledHandler);
