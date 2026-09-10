#pragma once
#import <Foundation/Foundation.h>
#include "CandidateSkin.h"

namespace metasequoia::mac {
struct SkinRemovalSnapshot {
    NSURL *directory;
    NSString *skinId;
    NSString *name;
    NSData *manifest;
    id resourceIdentifier;
};

inline NSError *SkinLibraryError(NSString *message)
{
    return [NSError errorWithDomain:@"MetasequoiaSkinLibrary" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

inline std::optional<SkinRemovalSnapshot> ReviewSkinRemoval(NSURL *root, NSString *skinId, NSError **error)
{
    const auto fail = [&]() -> std::optional<SkinRemovalSnapshot> {
        if (error) *error = SkinLibraryError(@"皮肤已变化或无法读取，请刷新列表后重试。");
        return std::nullopt;
    };
    if (!root.isFileURL || ![skinId isKindOfClass:NSString.class] ||
        !IsSafeSkinId(skinId.UTF8String) || IsBuiltInSkinId(skinId.UTF8String)) return fail();
    NSURL *directory = [root URLByAppendingPathComponent:skinId isDirectory:YES];
    NSNumber *isDirectory = nil, *isLink = nil;
    id resource = nil;
    if (![directory getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil] || !isDirectory.boolValue ||
        ![directory getResourceValue:&isLink forKey:NSURLIsSymbolicLinkKey error:nil] || isLink.boolValue ||
        ![directory getResourceValue:&resource forKey:NSURLFileResourceIdentifierKey error:nil] || !resource) return fail();
    const auto package = LoadSkinPackage(root.fileSystemRepresentation, skinId.UTF8String);
    if (!package) return fail();
    NSURL *manifestURL = [directory URLByAppendingPathComponent:@"skin.toml"];
    NSNumber *size = nil;
    if (![manifestURL getResourceValue:&size forKey:NSURLFileSizeKey error:nil] || size.unsignedLongLongValue > 65536) return fail();
    NSData *manifest = [NSData dataWithContentsOfURL:manifestURL options:0 error:nil];
    if (!manifest || manifest.length > 65536) return fail();
    return SkinRemovalSnapshot{directory, [skinId copy], @(package->name.c_str()), manifest, resource};
}

// Inject the native trash operation so regression tests never touch the user's Trash.
inline bool TrashReviewedSkin(const SkinRemovalSnapshot &reviewed,
                             BOOL (^trash)(NSURL *, NSError **), NSError **error)
{
    auto current = ReviewSkinRemoval(reviewed.directory.URLByDeletingLastPathComponent, reviewed.skinId, error);
    if (!current) return false;
    if (![current->manifest isEqual:reviewed.manifest] ||
        ![current->resourceIdentifier isEqual:reviewed.resourceIdentifier]) {
        if (error) *error = SkinLibraryError(@"确认期间皮肤已被修改，请刷新列表后重新确认。");
        return false;
    }
    return trash(current->directory, error);
}
inline bool RenameReviewedSkin(const SkinRemovalSnapshot &reviewed, NSString *name, NSError **error)
{
    auto current = ReviewSkinRemoval(reviewed.directory.URLByDeletingLastPathComponent, reviewed.skinId, error);
    if (!current) return false;
    if (![current->manifest isEqual:reviewed.manifest] || ![current->resourceIdentifier isEqual:reviewed.resourceIdentifier]) {
        if (error) *error = SkinLibraryError(@"确认期间皮肤已被修改，请刷新列表后重试。");
        return false;
    }
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        if (error) *error = SkinLibraryError(@"皮肤名称不能包含控制字符。");
        return false;
    }
    const char *utf8 = trimmed.UTF8String;
    const auto updated = RenameSkinManifest(std::string((const char *)current->manifest.bytes, current->manifest.length), utf8 ? utf8 : "");
    if (!updated) {
        if (error) *error = SkinLibraryError(@"请输入非空皮肤名称，不含控制字符且不超过 80 字节。");
        return false;
    }
    NSData *data = [NSData dataWithBytes:updated->data() length:updated->size()];
    return [data writeToURL:[current->directory URLByAppendingPathComponent:@"skin.toml"] options:NSDataWritingAtomic error:error];
}
} // namespace metasequoia::mac
