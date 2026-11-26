/* ASan/UBSan exercise of malformed data, lengths, and output boundaries. */
#define PWDHASH_NO_MAIN
#include "../src/cli/pwdhash.c"
#include <assert.h>

/* The rule for a notice, restated without the decoder: any byte outside visible ASCII, or one of
 * the characters a browser gives a meaning to, gets one. Everything else stays silent.
 */
static int plain_site(const unsigned char *site, size_t length) {
    size_t i;
    for (i=0;i<length;++i) if (site[i]<0x21||site[i]>=0x7f||strchr("#%:?@\\",site[i])) return 0;
    return 1;
}

int main(void) {
    static const char mostly_plain[]="abcXYZ019.-_/abcXYZ019.-_/abcXYZ019.-_/abcXYZ019.-_/ :#?@%\\\t";
    uint32_t random=0x50484446;
    unsigned char address[256], password[256], domain[257], site[257], guarded[28];
    char notice[256];
    size_t i,j,silent=0,noticed=0;
    assert(!pwdhash_self_test());
    for (i=0;i<40000;++i) {
        size_t address_length=i%256, password_length=(i*17)%256, domain_length=0, site_length=0, output_length=0;
        size_t capacity=i%7 ? sizeof notice-2 : 1+i%97, written;
        int rc, site_rc;
        for (j=0;j<256;++j) {
            random=random*1664525u+1013904223u; address[j]=(unsigned char)(random>>24);
            random=random*1664525u+1013904223u; password[j]=(unsigned char)(random>>24);
        }
        /* The second half uses addresses that are mostly ordinary names, so both outcomes are common. */
        if (i>=20000) for (j=0;j<256;++j) address[j]=(unsigned char)mostly_plain[address[j]%(sizeof mostly_plain-1)];
        memset(guarded,0xa5,sizeof guarded);
        site_rc=pwdhash_site_part(address,address_length,site,sizeof site,&site_length);
        assert(site_rc==0||site_rc==1);
        rc=pwdhash_domain(address,address_length,domain,sizeof domain,&domain_length);
        assert(rc==site_rc);
        if (!rc) {
            assert(domain_length<=address_length);
            /* The hashing domain is always the end of the site part the notice describes. */
            assert(domain_length<=site_length&&!memcmp(site+site_length-domain_length,domain,domain_length));
            memset(notice,0x5a,sizeof notice);
            written=pwdhash_site_caution(site,site_length,notice+1,capacity);
            assert(written<capacity&&notice[1+written]==0);
            assert(notice[0]==0x5a&&notice[1+capacity]==0x5a);
            for (j=0;j<written;++j) assert(notice[1+j]>=0x20&&notice[1+j]<0x7f);
            if (capacity>1) assert((written==0)==plain_site(site,site_length));
            if (written) ++noticed; else ++silent;
            rc=pwdhash_derive(domain,domain_length,password,password_length,guarded+1,&output_length);
            assert(rc==0||rc==3);
            assert(output_length<=26);
            assert(guarded[0]==0xa5&&guarded[27]==0xa5);
        }
        assert(pwdhash_domain(address,address_length,domain,address_length,&domain_length)==2);
        assert(pwdhash_site_part(address,address_length,site,address_length,&site_length)==2);
    }
    assert(silent>1000&&noticed>1000);
    assert(!pwdhash_site_caution(address,8,NULL,sizeof notice)&&!pwdhash_site_caution(address,8,notice,0));
    assert(!pwdhash_site_caution(NULL,0,notice,sizeof notice)&&!notice[0]);
    puts("PASS: C digest vectors and 40,000 malformed/boundary cases under sanitizers");
    return 0;
}
