#pragma once
#include <metasequoia/session.h>

inline metasequoia::SessionOptions SessionTestOptions(SchemeType scheme = SchemeType::Quanpin,
                                                     bool helpcode = true, bool learning = true)
{
    metasequoia::SessionOptions options;
    options.paths = metasequoia::RuntimePaths::legacy();
    options.scheme = scheme;
    options.helpcode = helpcode;
    options.learning = learning;
    return options;
}
