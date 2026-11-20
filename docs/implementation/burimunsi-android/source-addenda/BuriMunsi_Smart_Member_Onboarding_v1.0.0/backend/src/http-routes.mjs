import {aggregateSuggestions,enrollOne,importVerifiedRows,prepareImportRows,InputError} from './onboarding.mjs';
import {parseDocument} from './document-import.mjs';
/** Mount into existing authenticated Collect router. No direct anonymous endpoints. */
export function makeOnboardingHandlers({repository,store,authorize,ocrConfig,documentAdapters={}}) {
 const guard=async(req)=>{const principal=await authorize(req);if(!principal?.canEnroll||!principal.tenantId)throw Object.assign(new Error('Forbidden'),{status:403});return principal;};
 return {
  async suggestions(req){const actor=await guard(req);const events=await repository.listPayerEvidence(actor.tenantId);const members=await repository.listMemberPayerBindings(actor.tenantId);return aggregateSuggestions(events,members,{search:req.query?.search??'',limit:Math.min(100,Math.max(1,Number(req.query?.limit)||50))});},
  async enroll(req){const actor=await guard(req);return enrollOne({store,actor,tenantId:actor.tenantId,name:req.body?.momoName,phone:req.body?.momoNumber,candidateId:req.body?.candidateId??null,verifiedOwnership:req.body?.verifiedOwnership,acceptedTerms:req.body?.acceptedTerms,consentRecorded:req.body?.consentRecorded,idempotencyKey:req.headers?.['idempotency-key']});},
  async parseCsv(req){await guard(req);return prepareImportRows(req.body?.rows);},
  async parseImage(req){await guard(req);if(!req.file)throw new InputError('Missing image');return parseDocument({bytes:req.file.buffer,mimeType:req.file.mimetype,ocrConfig,adapters:documentAdapters});},
  async commitImport(req){const actor=await guard(req);return importVerifiedRows({store,actor,tenantId:actor.tenantId,rows:req.body?.rows,batchId:req.headers?.['idempotency-key']});}
 };
}
