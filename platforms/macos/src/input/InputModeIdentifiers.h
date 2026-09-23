#pragma once
#import <Foundation/Foundation.h>

// The two input modes Info.plist.in declares. The menu bar shows the active mode's icon, 中 or 英, which is how macOS carries the persistent Chinese/English indicator the Windows tray's language-bar icon provides. info-plist-names checks these literals against the plist.
static NSString *const MSIMEChineseInputModeID = @"app.msime.inputmethod.MetasequoiaIME.Hans";
static NSString *const MSIMEEnglishInputModeID = @"app.msime.inputmethod.MetasequoiaIME.Roman";

static inline NSString *MSIMEInputModeIDForEnglish(BOOL english) {
    return english ? MSIMEEnglishInputModeID : MSIMEChineseInputModeID;
}

static inline BOOL MSIMEIsInputModeID(id value) {
    return [value isKindOfClass:NSString.class] &&
           ([value isEqualToString:MSIMEChineseInputModeID] || [value isEqualToString:MSIMEEnglishInputModeID]);
}

static inline BOOL MSIMEEnglishForInputModeID(NSString *identifier) {
    return [identifier isEqualToString:MSIMEEnglishInputModeID];
}

// Keeps the system's selected input mode and the controller's Chinese/English state in step without either side echoing the other. The selected mode is global to the login session, so one state serves every controller instance.
//
// `current` is the mode last reported by the system or last requested by the controller; a report that repeats it is the system confirming what is already shown, not a user choice, so it does not flip the controller's state. `selecting` is set while the controller is asking the client to switch, so a report delivered synchronously from inside that call is not treated as a new choice either.
struct MSIMESystemInputModeState {
    NSString *current = nil;
    bool selecting = false;
};

// The system's selected input mode is global to the login session, so every controller instance shares one record of it. Leaving the input method clears it, so the first report after coming back is adopted even if it names the mode shown before leaving.
inline MSIMESystemInputModeState &MSIMESharedSystemInputModeState() {
    static MSIMESystemInputModeState state;
    return state;
}

static inline void MSIMEResetSystemInputModeState(MSIMESystemInputModeState &state) { state = MSIMESystemInputModeState{}; }

// Records a mode the system reported through setValue:forTag:client:. Returns YES when the controller should adopt it: a known mode that differs from the one already shown and that the controller did not just request itself.
static inline BOOL MSIMEAdoptReportedInputMode(MSIMESystemInputModeState &state, id value) {
    if (!MSIMEIsInputModeID(value)) return NO;
    const BOOL changed = ![value isEqualToString:state.current];
    state.current = [value copy];
    return changed && !state.selecting;
}

// Whether the system offers a mode for selection. A mode the user removed in System Settings, or one an install from before the English mode existed has not registered yet, cannot be selected, and asking for it would leave `current` naming a mode the menu bar does not show - the next report of the real one would then flip the controller's state back.
using MSIMEInputModeAvailability = BOOL (*)(NSString *identifier);

// Asks the client to show the mode matching `english`, unless it already does or the system does not offer it. Returns whether a switch was requested.
static inline BOOL MSIMESelectSystemInputMode(MSIMESystemInputModeState &state, BOOL english, id client,
                                              MSIMEInputModeAvailability available) {
    NSString *mode = MSIMEInputModeIDForEnglish(english);
    if (state.selecting || [mode isEqualToString:state.current] || ![client respondsToSelector:@selector(selectInputMode:)] ||
        !available || !available(mode))
        return NO;
    state.current = mode;
    state.selecting = true;
    [client performSelector:@selector(selectInputMode:) withObject:mode];
    state.selecting = false;
    return YES;
}
