import {openFixture} from './financial-approval.fixture.ts';
import {registerFinancialApprovalCohort} from './financial-approval.entrypoint.ts';
registerFinancialApprovalCohort(openFixture,'candidate_green11');
