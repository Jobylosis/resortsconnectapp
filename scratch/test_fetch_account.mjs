import { db } from '../website/src/firebase.js';
import { fetchCurrentOwnerGCashAccount } from '../website/src/utils/receiptValidator.js';

async function test() {
  try {
    console.log("Calling fetchCurrentOwnerGCashAccount with otiTL85PGUhhBSsv0JonFgvWIK73...");
    const res = await fetchCurrentOwnerGCashAccount(db, 'otiTL85PGUhhBSsv0JonFgvWIK73', {});
    console.log("Result for otiTL85PGUhhBSsv0JonFgvWIK73:", res);

    console.log("Calling fetchCurrentOwnerGCashAccount with casa-delrio (the id slug)...");
    const resSlug = await fetchCurrentOwnerGCashAccount(db, 'casa-delrio', { gcashName: 'Fallback Name', gcashNumber: '09123456789' });
    console.log("Result for slug:", resSlug);
  } catch (e) {
    console.error("Error:", e);
  }
}
test().then(() => process.exit(0));

