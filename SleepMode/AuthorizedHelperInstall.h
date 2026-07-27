#import <Security/Authorization.h>

OSStatus SMInstallPrivilegedHelper(
    AuthorizationRef authorization,
    const char *helperPath,
    uid_t userID
);
