// C side of the Go demo plugin: the exports the host looks for and thin
// wrappers around the host function table (cgo cannot call a C function
// pointer from Go directly).
#ifndef BRIDGE_H
#define BRIDGE_H

#include <stdint.h>

// Implemented in Go (main.go, //export).
int64_t goOnDocument(char *uri, char *mode, char *redirect, int64_t redirectCap);
void goShowInfo(void);
void goConfigure(void);
void goSettingsAnswer(char *controlId, char *valuesJson);

// Implemented in bridge.c; called from Go.
void bridgeSetStatus(const char *text);
int64_t bridgeShowDialog(const char *json);
// Dialog whose answer goes to goSettingsAnswer.
int64_t bridgeShowSettingsDialog(const char *json);
// Value length, -1 = never set, -2 = buffer too small.
int64_t bridgeGetSetting(const char *key, char *buf, int64_t size);
int64_t bridgeSetSetting(const char *key, const char *value);

#endif
