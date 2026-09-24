#import "VoiceSettings.h"

// What is left of this file is the data layer its header declares: the change notification the input method listens on, and — inline in the header, so that the voice form can read them without linking this file into the test executables that build it — the polish prompt presets and the Doubao authentication rule.
//
// It used to be a 25-line NSGridView window as well, and that window was the only place fourteen preferences the input method reads every recording could be set: the master switch, the five dictation hotkeys, the recognition language, the prompt sound, muting other audio, the streaming inline preedit and the polish prompt preset. Nothing ever called +sharedSettings, so none of them could be reached. They are controls on the 语音输入 and 按键 pages of the settings window now.
NSNotificationName const MSIMEVoiceSettingsDidChangeNotification = @"MSIMEClientVoiceSettingsDidChange";
