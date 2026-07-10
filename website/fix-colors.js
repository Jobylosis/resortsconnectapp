const fs = require('fs');
const path = require('path');
const dir = 'c:/Users/PC/GithubRepo/resortsconnectapp/website/src/components';
const walk = (d) => {
  let results = [];
  const list = fs.readdirSync(d);
  list.forEach(file => {
    file = path.join(d, file);
    const stat = fs.statSync(file);
    if (stat && stat.isDirectory()) { 
      results = results.concat(walk(file));
    } else if (file.endsWith('.js')) {
      results.push(file);
    }
  });
  return results;
};
const files = walk(dir);
let changedCount = 0;
files.forEach(file => {
  let content = fs.readFileSync(file, 'utf8');
  let newContent = content
    .replace(/'#FEF2F2'/g, "'rgba(239, 68, 68, 0.1)'")
    .replace(/'#EFF6FF'/g, "'rgba(59, 130, 246, 0.1)'")
    .replace(/'#ECFDF5'/g, "'rgba(16, 185, 129, 0.1)'")
    .replace(/#FEF2F2/g, "rgba(239, 68, 68, 0.1)")
    .replace(/#EFF6FF/g, "rgba(59, 130, 246, 0.1)")
    .replace(/#ECFDF5/g, "rgba(16, 185, 129, 0.1)");
  if (content !== newContent) {
    fs.writeFileSync(file, newContent, 'utf8');
    changedCount++;
    console.log('Updated: ' + file);
  }
});
console.log('Total files changed: ' + changedCount);
