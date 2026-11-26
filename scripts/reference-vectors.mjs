// Test-only original website execution. Uses synthetic credentials exclusively.
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const reference = path.join(root, 'Reference/pwdhash-website');
const context = vm.createContext({ document: { hashform: { domain: {}, sitePassword: {} } } });
for (const name of ['md5.js', 'hashed-password.js', 'domain-extractor.js', 'pwdhash.js']) {
  vm.runInContext(fs.readFileSync(path.join(reference, name), 'utf8'), context, { filename: name });
}
const addresses = [
  'example.com', 'http://www.example.com/', 'https://login.example.com/a?x=1',
  'a.example.co.uk', 'b.example.co.uk', 'a.co.uk', 'b.co.uk',
  'http://a.example.com.au/login', 'www.example.ac.jp', 'example.com:8443',
  'www.EXAMPLE.COM', 'HTTP://www.example.com/', '127.0.0.1', '[::1]:8080',
  'localhost', 'a.b.github.io', 'https://éxample.com/login', 'https://例子.中国/',
  ' https://www.example.com/ ', 'http://https://www.example.com/path',
  'example.com.', '//example.com/path', 'https://', '', '////',
  'user@example.com', 'a..b', 'example.com?x=1', 'https://host/path/other.com'
];
const passwords = [
  '', '@@', 'a', 'ab', 'abc', 'password', 'Password123', 'P@ssword123!',
  '@@password', '@@@@password', 'under_score', 'with space', '  spaced  ',
  'éàñ', 'e\u0301test', '中文密码', '🔒test😀', '@@\u0301combining',
  'x'.repeat(20), 'x'.repeat(21), 'x'.repeat(22), 'x'.repeat(23),
  'x'.repeat(24), 'x'.repeat(63), 'x'.repeat(64), 'x'.repeat(65),
  'long!'.repeat(40), '\u0100\u00ff\u0000test', '\n\tline'
];
const vectors = [];
function add(address, password) {
  context.document.hashform.domain.value = address;
  context.document.hashform.sitePassword.value = password;
  try {
    const domain = vm.runInContext('(new SPH_DomainExtractor()).extractDomain(document.hashform.domain.value)', context);
    const result = String(vm.runInContext('Generate()', context));
    vectors.push({ address, password, domain, result });
  } catch {
    vectors.push({ address, password, domain: null, result: null });
  }
}
for (const address of addresses) for (const password of passwords) add(address, password);
// Fixed seed makes failures repeatable. Include all historical suffixes.
const suffixes = fs.readFileSync(path.join(reference, 'domain-extractor.js'), 'utf8').match(/domains='([^']+)'/)[1].split('|');
for (const suffix of suffixes) add(`https://login.synthetic.${suffix}/path`, 'Synthetic_Password!');
let seed = 0x50484446;
const random = () => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed; };
const alphabet = Array.from('aAZ09_+@! é中😀🔒\u0301\u0100');
for (let i = 0; i < 5000; i++) {
  let password = i % 3 === 0 ? '@@' : '';
  const length = 1 + random() % 90;
  for (let j = 0; j < length; j++) password += alphabet[random() % alphabet.length];
  add(addresses[random() % addresses.length], password);
}
fs.mkdirSync(path.join(root, '.build'), { recursive: true });
fs.writeFileSync(path.join(root, '.build/reference-vectors.json'), JSON.stringify(vectors));
console.log(`Prepared ${vectors.length} synthetic reference cases from the unmodified website JavaScript.`);
