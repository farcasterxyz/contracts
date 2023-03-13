const fnameEncoded = process.argv[2];
const fnameBuffer = Buffer.from(fnameEncoded, 'base64').subarray(0, 16);

// verify there are no characters after NULL and filter out NULL characters
let nameEnded = false;
const fnameBytes = [];
for (const byte of fnameBuffer) {
    if (byte != 0 && nameEnded) {
        process.stdout.write(Buffer.from([+false]));
        return;
    }
    if (byte == 0) {
        nameEnded = true;
        continue;
    }
    fnameBytes.push(byte);
}

// verify name matches regex
const fname = Buffer.from(fnameBytes).toString('utf8');
const fnameRule = new RegExp(/^[a-z0-9][a-z0-9-]{0,15}$/);
const isValid = fnameRule.test(fname);
process.stdout.write(Buffer.from([+isValid]));