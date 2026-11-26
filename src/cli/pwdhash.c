/*
 * Standalone Stanford PwdHash-compatible implementation. C11 + POSIX, libc only.
 * The password constraints/domain extractor are based on Stanford PwdHash.
 * Copyright 2005 Collin Jackson. Original BSD notice is available with --license.
 * https://pwdhash.github.io/website/
 * Native application and terminal interface: Nenad Micic's personal hobby project.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Volatile stores keep the compiler from optimizing the cleanup away. */
static void wipe(void *memory, size_t length) {
    volatile unsigned char *p = (volatile unsigned char *)memory;
    while (length--) *p++ = 0;
}

typedef struct {
    uint32_t h[4];
    uint64_t bytes;
    unsigned char block[64];
    size_t used;
} md5_context;

static uint32_t rotate_left(uint32_t value, unsigned amount) {
    return (value << amount) | (value >> (32 - amount));
}

static void md5_transform(md5_context *ctx, const unsigned char block[64]) {
    static const uint32_t constants[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
        0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
        0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
        0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
        0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
        0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
    };
    static const unsigned shifts[64] = {
        7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,
        5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,
        4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,
        6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21
    };
    uint32_t words[16], a=ctx->h[0], b=ctx->h[1], c=ctx->h[2], d=ctx->h[3];
    unsigned i;
    for (i=0; i<16; ++i) {
        const unsigned char *p=block+4*i;
        words[i]=(uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);
    }
    for (i=0; i<64; ++i) {
        uint32_t f, old_d=d;
        unsigned g;
        if (i<16) { f=(b&c)|(~b&d); g=i; }
        else if (i<32) { f=(d&b)|(~d&c); g=(5*i+1)%16; }
        else if (i<48) { f=b^c^d; g=(3*i+5)%16; }
        else { f=c^(b|~d); g=(7*i)%16; }
        d=c; c=b;
        b+=rotate_left(a+f+constants[i]+words[g],shifts[i]);
        a=old_d;
    }
    ctx->h[0]+=a; ctx->h[1]+=b; ctx->h[2]+=c; ctx->h[3]+=d;
    wipe(words,sizeof words);
}

static void md5_init(md5_context *ctx) {
    memset(ctx,0,sizeof *ctx);
    ctx->h[0]=0x67452301; ctx->h[1]=0xefcdab89;
    ctx->h[2]=0x98badcfe; ctx->h[3]=0x10325476;
}

static void md5_update(md5_context *ctx, const unsigned char *input, size_t length) {
    ctx->bytes+=(uint64_t)length;
    while (length) {
        size_t n=64-ctx->used;
        if (n>length) n=length;
        memcpy(ctx->block+ctx->used,input,n);
        ctx->used+=n; input+=n; length-=n;
        if (ctx->used==64) { md5_transform(ctx,ctx->block); ctx->used=0; }
    }
}

static void md5_final(md5_context *ctx, unsigned char digest[16]) {
    unsigned char padding[72]={0x80};
    unsigned char bits[8];
    uint64_t length=ctx->bytes*8;
    size_t pad=ctx->used<56 ? 56-ctx->used : 120-ctx->used;
    unsigned i;
    for (i=0;i<8;++i) bits[i]=(unsigned char)(length>>(8*i));
    md5_update(ctx,padding,pad);
    md5_update(ctx,bits,8);
    for (i=0;i<16;++i) digest[i]=(unsigned char)(ctx->h[i/4]>>(8*(i%4)));
    wipe(ctx,sizeof *ctx); wipe(bits,sizeof bits); wipe(padding,sizeof padding);
}

static int word_unit(uint32_t unit) {
    return (unit>='A'&&unit<='Z')||(unit>='a'&&unit<='z')||(unit>='0'&&unit<='9')||unit=='_';
}

/* Strict UTF-8 input, converted to the low bytes of JavaScript UTF-16 units. */
static int next_utf8(const unsigned char *input, size_t length, size_t *position, uint32_t *codepoint) {
    uint32_t cp, minimum;
    unsigned extra, i;
    unsigned char first;
    if (*position>=length) return 0;
    first=input[(*position)++];
    if (first<0x80) { *codepoint=first; return 1; }
    if (first>=0xc2&&first<=0xdf) { cp=first&0x1f; extra=1; minimum=0x80; }
    else if (first>=0xe0&&first<=0xef) { cp=first&0x0f; extra=2; minimum=0x800; }
    else if (first>=0xf0&&first<=0xf4) { cp=first&7; extra=3; minimum=0x10000; }
    else return -1;
    if (extra>length-*position) return -1;
    for (i=0;i<extra;++i) {
        unsigned char next=input[(*position)++];
        if ((next&0xc0)!=0x80) return -1;
        cp=(cp<<6)|(next&0x3f);
    }
    if (cp<minimum||cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff)) return -1;
    *codepoint=cp;
    return 1;
}

static const char legacy_suffixes[]="ab.ca|ac.ac|ac.at|ac.be|ac.cn|ac.il|ac.in|ac.jp|ac.kr|ac.nz|ac.th|ac.uk|ac.za|adm.br|adv.br|agro.pl|ah.cn|aid.pl|alt.za|am.br|arq.br|art.br|arts.ro|asn.au|asso.fr|asso.mc|atm.pl|auto.pl|bbs.tr|bc.ca|bio.br|biz.pl|bj.cn|br.com|cn.com|cng.br|cnt.br|co.ac|co.at|co.il|co.in|co.jp|co.kr|co.nz|co.th|co.uk|co.za|com.au|com.br|com.cn|com.ec|com.fr|com.hk|com.mm|com.mx|com.pl|com.ro|com.ru|com.sg|com.tr|com.tw|cq.cn|cri.nz|de.com|ecn.br|edu.au|edu.cn|edu.hk|edu.mm|edu.mx|edu.pl|edu.tr|edu.za|eng.br|ernet.in|esp.br|etc.br|eti.br|eu.com|eu.lv|fin.ec|firm.ro|fm.br|fot.br|fst.br|g12.br|gb.com|gb.net|gd.cn|gen.nz|gmina.pl|go.jp|go.kr|go.th|gob.mx|gov.br|gov.cn|gov.ec|gov.il|gov.in|gov.mm|gov.mx|gov.sg|gov.tr|gov.za|govt.nz|gs.cn|gsm.pl|gv.ac|gv.at|gx.cn|gz.cn|hb.cn|he.cn|hi.cn|hk.cn|hl.cn|hn.cn|hu.com|idv.tw|ind.br|inf.br|info.pl|info.ro|iwi.nz|jl.cn|jor.br|jpn.com|js.cn|k12.il|k12.tr|lel.br|ln.cn|ltd.uk|mail.pl|maori.nz|mb.ca|me.uk|med.br|med.ec|media.pl|mi.th|miasta.pl|mil.br|mil.ec|mil.nz|mil.pl|mil.tr|mil.za|mo.cn|muni.il|nb.ca|ne.jp|ne.kr|net.au|net.br|net.cn|net.ec|net.hk|net.il|net.in|net.mm|net.mx|net.nz|net.pl|net.ru|net.sg|net.th|net.tr|net.tw|net.za|nf.ca|ngo.za|nm.cn|nm.kr|no.com|nom.br|nom.pl|nom.ro|nom.za|ns.ca|nt.ca|nt.ro|ntr.br|nx.cn|odo.br|on.ca|or.ac|or.at|or.jp|or.kr|or.th|org.au|org.br|org.cn|org.ec|org.hk|org.il|org.mm|org.mx|org.nz|org.pl|org.ro|org.ru|org.sg|org.tr|org.tw|org.uk|org.za|pc.pl|pe.ca|plc.uk|ppg.br|presse.fr|priv.pl|pro.br|psc.br|psi.br|qc.ca|qc.com|qh.cn|re.kr|realestate.pl|rec.br|rec.ro|rel.pl|res.in|ru.com|sa.com|sc.cn|school.nz|school.za|se.com|se.net|sh.cn|shop.pl|sk.ca|sklep.pl|slg.br|sn.cn|sos.pl|store.ro|targi.pl|tj.cn|tm.fr|tm.mc|tm.pl|tm.ro|tm.za|tmp.br|tourism.pl|travel.pl|tur.br|turystyka.pl|tv.br|tw.cn|uk.co|uk.com|uk.net|us.com|uy.com|vet.br|web.za|web.com|www.ro|xj.cn|xz.cn|yk.ca|yn.cn|za.com";

static int known_suffix(const unsigned char *suffix, size_t length) {
    const char *start=legacy_suffixes, *end;
    while (*start) {
        end=strchr(start,'|');
        if (!end) end=start+strlen(start);
        if ((size_t)(end-start)==length && !memcmp(start,suffix,length)) return 1;
        if (!*end) break;
        start=end+1;
    }
    return 0;
}

/* The site part is what the original website splits into labels: the address without the first
 * "http://" and the first "https://", wherever they are, up to the next "/" after any leading ones.
 * Public length-based API also supports embedded NULs in synthetic test inputs.
 * Returns 0 on success, 1 for an empty/slash-only address, 2 for insufficient room.
 * site may alias address, and capacity must allow address_length + 1 bytes.
 */
int pwdhash_site_part(const unsigned char *address, size_t address_length,
                      unsigned char *site, size_t capacity, size_t *site_length) {
    static const char *prefixes[]={"http://","https://"};
    size_t length=address_length, i, j, start, end;
    if (!address||!site||!site_length||capacity<=address_length) return 2;
    *site_length=0;
    memmove(site,address,length);
    for (j=0;j<2;++j) {
        size_t prefix_length=strlen(prefixes[j]);
        for (i=0;i+prefix_length<=length;++i) {
            if (!memcmp(site+i,prefixes[j],prefix_length)) {
                memmove(site+i,site+i+prefix_length,length-i-prefix_length);
                length-=prefix_length;
                break;
            }
        }
    }
    start=0;
    while (start<length&&site[start]=='/') ++start;
    end=start;
    while (end<length&&site[end]!='/') ++end;
    if (end==start) { site[0]=0; return 1; }
    length=end-start;
    memmove(site,site+start,length);
    site[length]=0; *site_length=length;
    return 0;
}

/* The hashing domain: the last two labels of the site part, or three for a historical suffix.
 * Same contract as pwdhash_site_part.
 */
int pwdhash_domain(const unsigned char *address, size_t address_length,
                   unsigned char *domain, size_t capacity, size_t *domain_length) {
    size_t length=0, i, start=0, count=0, previous=0, last=0;
    int status;
    if (!address||!domain||!domain_length||capacity<=address_length) return 2;
    *domain_length=0;
    status=pwdhash_site_part(address,address_length,domain,capacity,&length);
    if (status) return status;
    for (i=0;i<length;++i) if (domain[i]=='.') { previous=last; last=i; ++count; }
    if (count>=2) {
        size_t suffix_start=previous+1;
        if (known_suffix(domain+suffix_start,length-suffix_start)) {
            size_t dots=0;
            for (i=length;i>0;--i) {
                if (domain[i-1]=='.'&&++dots==3) { start=i; break; }
            }
        } else start=suffix_start;
    }
    length-=start;
    memmove(domain,domain+start,length);
    domain[length]=0; *domain_length=length;
    return 0;
}

/* Describes the first character of a site part that a browser and the original algorithm read
 * differently, or that is easy to enter without noticing. A pasted link can name one site to a
 * browser and another to the algorithm, and a stray invisible character changes the result.
 * Plain names such as "example.com" or "name.SUFFIX", in any letter case, never get a notice.
 * The algorithm stays as published: nothing is rejected, trimmed or rewritten here.
 * Writes printable ASCII whatever the input holds and returns its length, or 0 for no notice.
 */
size_t pwdhash_site_caution(const unsigned char *site, size_t site_length, char *notice, size_t capacity) {
    char name[48];
    const char *reason;
    size_t position=0, at=0;
    uint32_t cp=0;
    int rc, written;
    if (!notice||!capacity) return 0;
    notice[0]=0;
    if (!site) return 0;
    for (;;) {
        at=position;
        rc=next_utf8(site,site_length,&position,&cp);
        if (rc<=0||cp<0x21||cp>=0x7f||cp=='#'||cp=='%'||cp==':'||cp=='?'||cp=='@'||cp=='\\') break;
    }
    if (!rc) return 0;
    if (rc<0) {
        snprintf(name,sizeof name,"a byte that is not valid UTF-8 (0x%02X)",(unsigned)site[at]);
        reason="Check how the address was entered or encoded.";
    } else if (cp==':'&&position==site_length) {
        size_t shown=site_length>60 ? 60 : site_length;
        written=snprintf(notice,capacity,"Caution: only lowercase \"http://\" and \"https://\" are removed from an address. "
            "Here the original algorithm reads \"%.*s%s\" as the site name, so every address that starts this way gives the same result.",
            (int)shown,(const char *)site,shown<site_length ? "..." : "");
        return written<0 ? 0 : (size_t)written<capacity ? (size_t)written : capacity-1;
    } else {
        if (cp==0x20) snprintf(name,sizeof name,"a space");
        else if (cp==0x09) snprintf(name,sizeof name,"a tab");
        else if ((cp>=0x0a&&cp<=0x0d)||cp==0x85||cp==0x2028||cp==0x2029) snprintf(name,sizeof name,"a line break");
        else if (cp<0x20||(cp>=0x7f&&cp<0xa0)) snprintf(name,sizeof name,"a control character (U+%04lX)",(unsigned long)cp);
        else if (cp<0x7f) snprintf(name,sizeof name,"\"%c\"",(int)cp);
        else snprintf(name,sizeof name,"a non-ASCII character (U+%04lX)",(unsigned long)cp);
        if (cp==':') reason="The original algorithm does not separate a port or user name from the site name, so the result can differ from the same site without it.";
        else if (cp=='#'||cp=='?'||cp=='\\') reason="A browser ends the site name there, but the original algorithm reads on, so the hashing domain may not be the site a link opens.";
        else if (cp=='@') reason="A browser treats the text before it as a user name, so the hashing domain may not be the site a link opens.";
        else if (cp=='%') reason="A browser decodes percent codes in a site name, but the original algorithm hashes them as written.";
        else if (cp<0x80) reason="Nothing is trimmed, so the result can differ from the same address without it.";
        else reason="The original algorithm keeps only part of each non-ASCII character, so different names can give the same password.";
    }
    written=snprintf(notice,capacity,"Caution: the site part of the address contains %s. %s",name,reason);
    return written<0 ? 0 : (size_t)written<capacity ? (size_t)written : capacity-1;
}

static unsigned char next_extra(const unsigned char hash[22], size_t *index) {
    return *index<22 ? hash[(*index)++] : 0;
}

static int contains_range(const unsigned char *text, size_t length, unsigned char lower, unsigned char upper) {
    size_t i;
    for (i=0;i<length;++i) if (text[i]>=lower&&text[i]<=upper) return 1;
    return 0;
}

/* Output capacity is always 26 bytes. Result length is explicit: the original
 * algorithm can produce embedded NUL bytes for long input passwords.
 * Returns 0 on success, 3 for malformed UTF-8. Allows an empty reference key.
 */
int pwdhash_derive(const unsigned char *domain, size_t domain_length,
                   const unsigned char *password, size_t password_length,
                   unsigned char output[26], size_t *output_length) {
    static const unsigned char alphabet[]="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    unsigned char key[64]={0}, hashed_key[16]={0}, pad[64], digest[16], inner[16], hash[22], rotated[26];
    md5_context key_context, ctx;
    size_t position=0, units=0, i, j=0, start, n, extra, rotation;
    uint32_t cp;
    int status=0, wants_symbol=0, rc;
    *output_length=0;
    memset(output,0,26);
    memset(&ctx,0,sizeof ctx);
    md5_init(&key_context);
    if (password_length>=2&&password[0]=='@'&&password[1]=='@') position=2;
    while (position<password_length) {
        unsigned char low[2];
        size_t count=1;
        rc=next_utf8(password,password_length,&position,&cp);
        if (rc<0) { status=3; goto cleanup; }
        if (cp>0xffff) {
            uint32_t value=cp-0x10000;
            low[0]=(unsigned char)(0xd800+(value>>10));
            low[1]=(unsigned char)(0xdc00+(value&0x3ff));
            count=2; wants_symbol=1;
        } else { low[0]=(unsigned char)cp; if (!word_unit(cp)) wants_symbol=1; }
        md5_update(&key_context,low,count);
        for (i=0;i<count;++i) { if (units<64) key[units]=low[i]; ++units; }
        wipe(low,sizeof low);
    }
    md5_final(&key_context,hashed_key);
    if (units>64) { memcpy(key,hashed_key,16); memset(key+16,0,48); }
    for (i=0;i<64;++i) pad[i]=key[i]^0x36;
    md5_init(&ctx); md5_update(&ctx,pad,64);
    position=0;
    while (position<domain_length) {
        unsigned char low[2];
        size_t count=1;
        rc=next_utf8(domain,domain_length,&position,&cp);
        if (rc<0) { status=3; goto cleanup; }
        if (cp>0xffff) {
            uint32_t value=cp-0x10000;
            low[0]=(unsigned char)(0xd800+(value>>10));
            low[1]=(unsigned char)(0xdc00+(value&0x3ff)); count=2;
        } else low[0]=(unsigned char)cp;
        md5_update(&ctx,low,count); wipe(low,sizeof low);
    }
    md5_final(&ctx,inner);
    for (i=0;i<64;++i) pad[i]=key[i]^0x5c;
    md5_init(&ctx); md5_update(&ctx,pad,64); md5_update(&ctx,inner,16); md5_final(&ctx,digest);
    for (i=0;i<16;i+=3) {
        uint32_t group=(uint32_t)digest[i]<<16;
        if (i+1<16) group|=(uint32_t)digest[i+1]<<8;
        if (i+2<16) group|=digest[i+2];
        hash[j++]=alphabet[(group>>18)&63]; hash[j++]=alphabet[(group>>12)&63];
        if (i+1<16) hash[j++]=alphabet[(group>>6)&63];
        if (i+2<16) hash[j++]=alphabet[group&63];
    }
    start=units>2 ? units-2 : 0;
    if (start>22) start=22;
    memcpy(output,hash,start); n=start; extra=start;
    output[n]=contains_range(output,n,'A','Z') ? next_extra(hash,&extra) : (unsigned char)('A'+next_extra(hash,&extra)%26); ++n;
    output[n]=contains_range(output,n,'a','z') ? next_extra(hash,&extra) : (unsigned char)('a'+next_extra(hash,&extra)%26); ++n;
    output[n]=contains_range(output,n,'0','9') ? next_extra(hash,&extra) : (unsigned char)('0'+next_extra(hash,&extra)%10); ++n;
    for (i=0;i<n&&word_unit(output[i]);++i) {}
    output[n]=(i<n&&wants_symbol) ? next_extra(hash,&extra) : '+'; ++n;
    if (!wants_symbol) for (i=0;i<n;++i) if (!word_unit(output[i])) output[i]=(unsigned char)('A'+next_extra(hash,&extra)%26);
    rotation=next_extra(hash,&extra)%n;
    for (i=0;i<n;++i) rotated[i]=output[(i+rotation)%n];
    memcpy(output,rotated,n); *output_length=n;
cleanup:
    wipe(key,sizeof key); wipe(hashed_key,sizeof hashed_key); wipe(pad,sizeof pad);
    wipe(digest,sizeof digest); wipe(inner,sizeof inner); wipe(hash,sizeof hash); wipe(rotated,sizeof rotated);
    wipe(&ctx,sizeof ctx); wipe(&key_context,sizeof key_context);
    if (status) wipe(output,26);
    return status;
}

int pwdhash_self_test(void) {
    static const char *messages[]={"","a","abc","message digest","abcdefghijklmnopqrstuvwxyz"};
    static const char *expected[]={"d41d8cd98f00b204e9800998ecf8427e","0cc175b9c0f1b6a831c399e269772661","900150983cd24fb0d6963f7d28e17f72","f96b697d7cb7938d525a2f31aaf161d0","c3fcd3d76192e4007dfb496cca67e13b"};
    static const char hex[]="0123456789abcdef";
    unsigned char digest[16];
    char text[33];
    size_t i,j;
    for (i=0;i<sizeof messages/sizeof messages[0];++i) {
        md5_context ctx;
        md5_init(&ctx); md5_update(&ctx,(const unsigned char *)messages[i],strlen(messages[i])); md5_final(&ctx,digest);
        for (j=0;j<16;++j) { text[j*2]=hex[digest[j]>>4]; text[j*2+1]=hex[digest[j]&15]; }
        text[32]=0;
        if (strcmp(text,expected[i])) { wipe(digest,sizeof digest); return 1; }
    }
    wipe(digest,sizeof digest); wipe(text,sizeof text);
    return 0;
}

#ifndef PWDHASH_NO_MAIN
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/select.h>
#include <termios.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach/mach_time.h>
#endif

#ifndef PWDHASH_IDLE_SECONDS
#define PWDHASH_IDLE_SECONDS 300
#endif
#define INPUT_LIMIT 65536
static volatile sig_atomic_t interrupted=0;
static void interrupt_input(int signum) { interrupted=signum; }

static double continuous_seconds(void) {
#if defined(__APPLE__)
    mach_timebase_info_data_t scale;
    mach_timebase_info(&scale);
    return (double)mach_continuous_time()*(double)scale.numer/(double)scale.denom/1e9;
#else
    struct timespec now;
#if defined(CLOCK_BOOTTIME)
    clock_gettime(CLOCK_BOOTTIME,&now);
#else
    clock_gettime(CLOCK_MONOTONIC,&now);
#endif
    return (double)now.tv_sec+(double)now.tv_nsec/1e9;
#endif
}

/* Writes everything, or reports failure. Used for the result too, so no copy of it stays in a
 * stdio buffer.
 */
static int write_all(int fd, const void *data, size_t length) {
    const unsigned char *next=data;
    while (length) {
        ssize_t sent=write(fd,next,length);
        if (sent<=0) { if (sent<0&&errno==EINTR&&!interrupted) continue; return 1; }
        next+=sent; length-=(size_t)sent;
    }
    return 0;
}

static int valid_utf8(const unsigned char *text, size_t length) {
    size_t position=0;
    uint32_t cp;
    int rc;
    while ((rc=next_utf8(text,length,&position,&cp))>0) {}
    return !rc;
}

/* No stdio buffering of secret input. Interactive secrets are read with echo
 * and canonical buffering disabled. Backspace and Ctrl-U remain available.
 * The wait uses select() because poll() rejects terminal devices on macOS, and the descriptor
 * stays blocking because standard input's flags are shared with other processes.
 */
static int read_line(int fd, unsigned char *buffer, size_t *length, int secret, const char *prompt) {
    struct termios saved, edited;
    int terminal, changed=0, status=0, escape=0;
    double deadline=continuous_seconds()+PWDHASH_IDLE_SECONDS;
    *length=0;
    if (fd<0||fd>=FD_SETSIZE) return 1;
    terminal=isatty(fd);
    if (terminal&&secret) {
        if (tcgetattr(fd,&saved)) return 1;
        edited=saved; edited.c_lflag&=(tcflag_t)~(ECHO|ECHONL|ICANON);
        edited.c_cc[VMIN]=1; edited.c_cc[VTIME]=0;
        if (tcsetattr(fd,TCSAFLUSH,&edited)) return 1;
        changed=1;
    }
    if (prompt) (void)write_all(fd,prompt,strlen(prompt));
    while (!interrupted) {
        unsigned char byte;
        fd_set readable;
        struct timeval wait;
        double remaining=deadline-continuous_seconds();
        int ready;
        ssize_t got;
        if (remaining<=0) { status=2; break; }
        if (remaining>1) remaining=1;
        wait.tv_sec=(time_t)remaining;
        wait.tv_usec=(suseconds_t)((remaining-(double)wait.tv_sec)*1e6);
        FD_ZERO(&readable); FD_SET(fd,&readable);
        ready=select(fd+1,&readable,NULL,NULL,&wait);
        if (ready<0) { if (errno==EINTR) continue; status=1; break; }
        if (!ready) continue;
        got=read(fd,&byte,1);
        if (got<0) { if (errno==EINTR||errno==EAGAIN||errno==EWOULDBLOCK) continue; status=1; break; }
        if (!got) { if (!*length) status=1; break; }
        deadline=continuous_seconds()+PWDHASH_IDLE_SECONDS;
        if (byte=='\n'||(terminal&&byte=='\r')) break;
        if (terminal&&secret) {
            if (escape) {
                if (escape==1&&(byte=='['||byte=='O')) { escape=2; continue; }
                if (escape==1||(byte>=0x40&&byte<=0x7e)) escape=0;
                continue;
            }
            if (byte==27) { escape=1; continue; }
            if (byte==127||byte==8) {
                if (*length) {
                    size_t previous=*length-1;
                    while (previous&&(buffer[previous]&0xc0)==0x80) --previous;
                    wipe(buffer+previous,*length-previous); *length=previous;
                }
                continue;
            }
            if (byte==21) { wipe(buffer,*length); *length=0; continue; }
            if (byte==4) { if (!*length) status=1; break; }
            if (byte<32&&byte!='\t') continue;
        }
        if (*length==INPUT_LIMIT) { status=3; break; }
        buffer[(*length)++]=byte;
    }
    if (interrupted) status=4;
    if (changed) {
        if (status) (void)tcflush(fd,TCIFLUSH);
        if (tcsetattr(fd,TCSAFLUSH,&saved)) status=1;
        (void)write_all(fd,"\n",1);
    }
    if (status) { wipe(buffer,*length); *length=0; }
    buffer[*length]=0;
    return status;
}

static void usage(FILE *stream) {
    fputs("Usage: pwdhash [--stdin] [--hex] [--no-newline] [SITE]\n"
          "       pwdhash --self-test | --version | --license | --help\n\n"
          "Prompts for a hidden site password using the terminal. With no SITE,\n"
          "prompts for the address too. --stdin reads one UTF-8 password line\n"
          "from standard input for pipelines; no password argument is accepted.\n"
          "--hex prints exact output bytes as hexadecimal, including legacy NULs.\n"
          "Input expires after 5 idle minutes; input buffers are cleared on exit.\n"
          "Interactive editing: Backspace deletes; Ctrl-U clears the password.\n\n"
          "A SITE given as an argument can be seen by other programs and users of\n"
          "this computer (for example with ps) and is usually saved in shell history.\n"
          "Leave it out to be prompted for it instead.\n\n"
          "A caution about an unusual address, a password line ending in a carriage\n"
          "return, or NUL bytes in the result goes to standard error. The result\n"
          "itself is always exactly what the original website produces.\n\n"
          "Stanford PwdHash: https://pwdhash.github.io/website/\n"
          "Personal hobby project by Nenad Micic. Contact: pwdhash@nmic.app\n",stream);
}

static const char original_license[]=
"Stanford PwdHash algorithm and domain extraction\n\n"
"Copyright 2005 Collin Jackson\n"
"\n"
"Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:\n"
"\n"
"    * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.\n"
"    * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.\n"
"    * Neither the name of Stanford University nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.\n"
"\n"
"THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.\n";

int main(int argc, char **argv) {
    unsigned char address[INPUT_LIMIT+1]={0}, password[INPUT_LIMIT+1]={0}, domain[INPUT_LIMIT+1]={0}, result[26]={0};
    unsigned char line[2*sizeof result+1]={0};
    char notice[512]={0};
    size_t address_length=0, password_length=0, domain_length=0, result_length=0, line_length=0, i;
    const char *site=NULL;
    int use_stdin=0, hexadecimal=0, newline=1, fd=-1, status=1, rc;
    struct sigaction action;
    memset(&action,0,sizeof action); action.sa_handler=interrupt_input; sigemptyset(&action.sa_mask);
    sigaction(SIGINT,&action,NULL); sigaction(SIGTERM,&action,NULL); sigaction(SIGHUP,&action,NULL);
    sigaction(SIGQUIT,&action,NULL); sigaction(SIGTSTP,&action,NULL); sigaction(SIGPIPE,&action,NULL);
    for (i=1;i<(size_t)argc;++i) {
        if (!strcmp(argv[i],"--help")||!strcmp(argv[i],"-h")) { usage(stdout); return 0; }
        if (!strcmp(argv[i],"--version")) { puts("pwdhash 1.0 (Stanford PwdHash compatible)"); return 0; }
        if (!strcmp(argv[i],"--license")) { fputs(original_license,stdout); return 0; }
        if (!strcmp(argv[i],"--self-test")) { rc=pwdhash_self_test(); puts(rc ? "Self-test FAILED" : "Self-test passed"); return rc; }
        if (!strcmp(argv[i],"--stdin")) use_stdin=1;
        else if (!strcmp(argv[i],"--hex")) hexadecimal=1;
        else if (!strcmp(argv[i],"--no-newline")) newline=0;
        else if (!strcmp(argv[i],"--")) { if (++i<(size_t)argc&&i+1==(size_t)argc&&!site) site=argv[i]; else { usage(stderr); goto cleanup; } }
        else if (argv[i][0]=='-'||site) { usage(stderr); goto cleanup; }
        else site=argv[i];
    }
    const struct rlimit no_core_files = { .rlim_cur = 0, .rlim_max = 0 };
    if (setrlimit(RLIMIT_CORE, &no_core_files) != 0) {
        fputs("Could not disable core files.\n", stderr);
        goto cleanup;
    }
    if (!use_stdin||!site) fd=open("/dev/tty",O_RDWR|O_CLOEXEC);
    if ((!use_stdin||!site)&&fd<0) { fputs("No terminal. Provide SITE and use --stdin to read a password from a pipe.\n",stderr); goto cleanup; }
    if (site) {
        address_length=strlen(site);
        if (address_length>INPUT_LIMIT) { fputs("Site address is too long.\n",stderr); goto cleanup; }
        memcpy(address,site,address_length);
    } else {
        rc=read_line(fd,address,&address_length,0,"Site Address: ");
        if (rc) {
            fputs("Site address input cancelled or timed out.\n",stderr);
            if (interrupted) status=128+interrupted;
            goto cleanup;
        }
    }
    /* The notice is about the whole site part, because the hashing domain is only its last labels. */
    rc=pwdhash_site_part(address,address_length,domain,sizeof domain,&domain_length);
    if (!rc&&pwdhash_site_caution(domain,domain_length,notice,sizeof notice)) { fputs(notice,stderr); fputc('\n',stderr); }
    if (rc||pwdhash_domain(address,address_length,domain,sizeof domain,&domain_length)) { fputs("Enter a site address.\n",stderr); goto cleanup; }
    /* A password that cannot be used is not asked for. */
    if (!valid_utf8(domain,domain_length)) { fputs("Input must be valid UTF-8.\n",stderr); goto cleanup; }
    rc=read_line(use_stdin ? STDIN_FILENO : fd,password,&password_length,1,use_stdin ? NULL : "Site Password: ");
    if (rc) {
        fputs(rc==2 ? "Input cleared after 5 idle minutes.\n" : "Password input cancelled or too long.\n",stderr);
        if (interrupted) status=128+interrupted;
        goto cleanup;
    }
    if (!password_length) { fputs("Enter a site password.\n",stderr); goto cleanup; }
    /* Only a terminal's line ending is removed. A line from a file or pipe keeps a carriage return. */
    if (password[password_length-1]=='\r') fputs("Caution: the password line ends with a carriage return, which is hashed as part of the password. Windows line endings add one.\n",stderr);
    if (pwdhash_derive(domain,domain_length,password,password_length,result,&result_length)) { fputs("Input must be valid UTF-8.\n",stderr); goto cleanup; }
    wipe(password,sizeof password);
    if (interrupted) { fputs("Cancelled before the result was written.\n",stderr); status=128+interrupted; goto cleanup; }
    if (hexadecimal) {
        static const char digits[]="0123456789abcdef";
        for (i=0;i<result_length;++i) {
            line[line_length++]=(unsigned char)digits[result[i]>>4];
            line[line_length++]=(unsigned char)digits[result[i]&15];
        }
    } else {
        if (memchr(result,0,result_length)) fputs("The original result includes invisible NUL bytes; --hex shows the exact bytes.\n",stderr);
        memcpy(line,result,result_length); line_length=result_length;
    }
    if (newline) line[line_length++]='\n';
    if (write_all(STDOUT_FILENO,line,line_length)) { if (interrupted) status=128+interrupted; goto cleanup; }
    status=0;
cleanup:
    wipe(address,sizeof address); wipe(password,sizeof password); wipe(domain,sizeof domain);
    wipe(result,sizeof result); wipe(line,sizeof line); wipe(notice,sizeof notice);
    if (fd>=0) close(fd);
    return status;
}
#endif
