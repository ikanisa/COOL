import {createHandler} from '../_shared/edge-http-handler.js';

Deno.serve(createHandler('admin-api'));
