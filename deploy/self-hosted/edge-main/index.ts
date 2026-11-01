// Closed Collect router. Each handler performs its own verified user/session,
// signed-hook or scheduler-token admission before any business effect.
// Never automatically replay a request after an uncertain worker failure.
import {createRouter} from './router.ts';
Deno.serve(createRouter(Deno.env.toObject()));
