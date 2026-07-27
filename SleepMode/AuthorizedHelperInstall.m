#import "AuthorizedHelperInstall.h"

#include <stdio.h>
#include <string.h>

OSStatus SMInstallPrivilegedHelper(
    AuthorizationRef authorization,
    const char *helperPath,
    uid_t userID
) {
    char userIDString[32];
    snprintf(userIDString, sizeof(userIDString), "%u", userID);
    char *arguments[] = {
        "--install",
        userIDString,
        NULL
    };
    FILE *output = NULL;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = AuthorizationExecuteWithPrivileges(
        authorization,
        helperPath,
        kAuthorizationFlagDefaults,
        arguments,
        &output
    );
#pragma clang diagnostic pop

    if (status != errAuthorizationSuccess) {
        return status;
    }

    char response[16] = {0};
    bool succeeded = output != NULL && fgets(
        response,
        sizeof(response),
        output
    ) != NULL && strncmp(response, "OK", 2) == 0;

    if (output != NULL) {
        fclose(output);
    }
    return succeeded ? errAuthorizationSuccess : errAuthorizationInternal;
}
