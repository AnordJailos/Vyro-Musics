// Usage: npm run make-admin -- someone@example.com
// Makes a person with a confirmed email an administrator. Needs DATABASE_URL.
import { promoteAdmins } from './admins.js';
import { pgDb } from './db.js';

const url = process.env.DATABASE_URL;
const emails = process.argv.slice(2);
if (!url || emails.length === 0) {
  console.error('Usage: DATABASE_URL=... npm run make-admin -- someone@example.com');
  process.exit(1);
}
const db = await pgDb(url);
const n = await promoteAdmins(db, emails);
console.log(n > 0 ? `${n} account(s) are now administrators.` : 'No change: the account must exist, have a confirmed email, and not be an administrator already.');
await db.close();
