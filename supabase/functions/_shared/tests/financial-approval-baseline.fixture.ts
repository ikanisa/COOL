// Intentional failing historical counterexample; execute explicitly, never in ordinary test discovery.
import {openFixture} from './financial-approval.fixture.ts';
import {registerFinancialApprovalCohort} from './financial-approval.entrypoint.ts';
registerFinancialApprovalCohort(openFixture,'baseline_red');
