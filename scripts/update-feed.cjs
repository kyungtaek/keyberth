const fs=require('node:fs'),path=require('node:path');
const [directory,version,arch]=process.argv.slice(2);
if(!/^\d+\.\d+\.\d+$/.test(version)||arch!=='arm64') throw Error('Invalid stable release target');
const asset='Keyberth-'+version+'-macOS-'+arch+'.zip';
if (!fs.statSync(path.join(directory,asset)).size) throw Error('Missing update ZIP');
const url='https://github.com/kyungtaek/keyberth/releases/download/v'+version+'/'+asset;
const feed={currentRelease:version,releases:[{version,updateTo:{version,url,name:'Keyberth '+version,pub_date:new Date().toISOString()}}]};
fs.writeFileSync(path.join(directory,'releases-'+arch+'.json'),JSON.stringify(feed,null,2)+'\n');
