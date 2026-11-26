# Compatibility reference

The four unmodified JavaScript files in `pwdhash-website/` come from
<https://github.com/pwdhash/website>. The public page is
<https://pwdhash.github.io/website/>. The files retain their original headers.
See [NOTICE](../NOTICE) for the upstream licence terms and attributions.

These files run only in the tests. The Apple apps share a Swift implementation
using Apple's CryptoKit HMAC-MD5. Android uses standard Java MD5 primitives;
the standalone C tool contains its own MD5/HMAC implementation. All preserve
the website's original domain extraction, low-byte UTF-16 encoding and output
constraints. None of the apps contains a browser or JavaScript engine.
