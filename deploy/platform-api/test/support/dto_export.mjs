import {lstat,realpath,writeFile} from 'node:fs/promises';
import {isAbsolute,resolve,sep} from 'node:path';
import {fileURLToPath} from 'node:url';

const sourceRoot=resolve(fileURLToPath(new URL('../../',import.meta.url)));

// Routine tests are read-only with respect to authored DTO fixtures. Regenerate
// examples only into a caller-selected, existing directory outside this source.
export async function exportDtos(name,value,directory=process.env.COLLECT_TEST_DTO_OUTPUT_DIR){
  if(!directory)return false;
  if(!/^admin-[a-z-]+-examples\.json$/.test(name)||!isAbsolute(directory))throw new Error('Invalid DTO export destination.');
  const target=resolve(directory);
  if(target===sourceRoot||target.startsWith(sourceRoot+sep))throw new Error('DTO exports cannot overwrite source fixtures.');
  const info=await lstat(target);
  if(!info.isDirectory()||info.isSymbolicLink()||await realpath(target)!==target)throw new Error('DTO export directory must be physical.');
  await writeFile(resolve(target,name),JSON.stringify(value,null,2)+'\n',{mode:0o600,flag:'wx'});
  return true;
}
