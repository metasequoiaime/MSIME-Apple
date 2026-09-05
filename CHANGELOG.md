# Changelog

## [0.44.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.43.1...v0.44.0) (2026-09-05)


### Features

* **mac:** use shared Engine voice and consolidated data sources ([9c1ac5e](https://github.com/metasequoiaime/MSIME-Apple/commit/9c1ac5e0d6054f06c97fa461d9378cc0a440bde7))

## [0.43.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.43.0...v0.43.1) (2026-09-05)


### Bug Fixes

* **mac:** stop annotating and converting local-mode candidates ([628009b](https://github.com/metasequoiaime/MSIME-Apple/commit/628009b1481225e716bb07c45b4bd7e5efd5045a))

## [0.43.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.42.0...v0.43.0) (2026-09-05)


### Features

* **ios:** reach the engine's local input modes ([741d523](https://github.com/metasequoiaime/MSIME-Apple/commit/741d5234ba1f4bb335bd967dd5e9def63ed3013b))
* **mac:** reach the engine's local input modes ([1d74932](https://github.com/metasequoiaime/MSIME-Apple/commit/1d74932a3bbdabd8174d02ee35a4a1b3b885ee93))


### Bug Fixes

* **input:** render shared partial composition and flush host transitions ([b11cf96](https://github.com/metasequoiaime/MSIME-Apple/commit/b11cf96e11c13de39689fd33b3b23b1f15ca4200))
* **ios:** finish pending composition before return and direct-mode input ([3699a0b](https://github.com/metasequoiaime/MSIME-Apple/commit/3699a0bea79ba85617875672b1c2d560c613afce))
* **ios:** keep every candidate commit on the visible page ([1d96158](https://github.com/metasequoiaime/MSIME-Apple/commit/1d96158e0f270a22b7c13d402841ada8f718f859))
* **ios:** stop the keyboard reporting local modes it cannot enter ([ee912d0](https://github.com/metasequoiaime/MSIME-Apple/commit/ee912d0cdf0b088e5afbac9fca54b9586e0d7027))
* **mac:** keep the highlighted candidate when a commit happens automatically ([7840d3f](https://github.com/metasequoiaime/MSIME-Apple/commit/7840d3f1b841cf2443ad6bb246ce024fdc98b449))

## [0.42.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.41.1...v0.42.0) (2026-09-05)


### Features

* **ios:** page through candidates past the ninth ([9205bdb](https://github.com/metasequoiaime/MSIME-Apple/commit/9205bdb29a3d12876702ef0772a6f712124b0665))
* **ios:** report engine diagnostics in the keyboard ([7b8be3b](https://github.com/metasequoiaime/MSIME-Apple/commit/7b8be3b0efda09c3b104f319050c2358ae29161b))
* **ios:** show double-pinyin hints on the keys ([c4f052d](https://github.com/metasequoiaime/MSIME-Apple/commit/c4f052d86863139319c3874f14974f46cc76ec11))


### Bug Fixes

* **ios:** keep the key hints on one line ([7ea9081](https://github.com/metasequoiaime/MSIME-Apple/commit/7ea9081520ff4c9cf763f20a4d8c1a052651cbb6))

## [0.41.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.41.0...v0.41.1) (2026-09-05)


### Bug Fixes

* **dictionary:** hold the fetched database to committed digests ([7a92195](https://github.com/metasequoiaime/MSIME-Apple/commit/7a921952875b9aca29d5c42aee38bf8496e1f32f))
* **dictionary:** 按提交的摘要校验词库,并补上 [#234](https://github.com/metasequoiaime/MSIME-Apple/issues/234) 漏掉的归属声明 ([fbba79a](https://github.com/metasequoiaime/MSIME-Apple/commit/fbba79a357d836a25f3691838fe40a6d79342358))
* **ios:** stop announcing the settings row icons ([e1bca55](https://github.com/metasequoiaime/MSIME-Apple/commit/e1bca55a6e6a96d10c06695d1fd234225c01dcad))
* **mac:** 遵循每页候选数量设置，并让窗口尺寸适应内容 ([309bec1](https://github.com/metasequoiaime/MSIME-Apple/commit/309bec1314eb7621faf3a913703580f3e6decad4))


### Reverts

* move back off calendar versioning ([df803f9](https://github.com/metasequoiaime/MSIME-Apple/commit/df803f95e5a4aaa2327e02fb98c09ddf984de628))
* move back off calendar versioning ([dd59d10](https://github.com/metasequoiaime/MSIME-Apple/commit/dd59d10ab0847b0390cbc82c7cebc863f8542c83))

## [0.41.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.40.0...v0.41.0) (2026-09-05)


### Features

* **dict:** 从 MSIME-Dict release 取词库，删掉 Dict submodule ([3623e3b](https://github.com/metasequoiaime/MSIME-Apple/commit/3623e3be8f609bcd89cc031ea4350f91ce0c6c51))

## [0.40.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.39.4...v0.40.0) (2026-09-05)


### Features

* **ios:** add traditional Chinese output ([d5cc70b](https://github.com/metasequoiaime/MSIME-Apple/commit/d5cc70b4bb7a073e39ea89ea4058f536013fbc93))


### Bug Fixes

* **ios:** give every generated target a product name ([304018b](https://github.com/metasequoiaime/MSIME-Apple/commit/304018bb46f7a76663f7f44c8d8fc322dbc07d4f))
* **ios:** open the compact dictionary with URI handling ([f993b7c](https://github.com/metasequoiaime/MSIME-Apple/commit/f993b7c26509f2e4e9bf15b35caf36b85a110987))

## [0.39.4](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.39.3...v0.39.4) (2026-09-05)


### Bug Fixes

* **release:** wait for the pull request's own checks before merging ([#230](https://github.com/metasequoiaime/MSIME-Apple/issues/230)) ([8da6573](https://github.com/metasequoiaime/MSIME-Apple/commit/8da65738b9c9e21c107adc2e001542f817cb40fe))

## [0.39.3](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.39.2...v0.39.3) (2026-09-05)


### Bug Fixes

* **apple:** keep the engine's helpcode and English paths out of the Apple frontends ([c288592](https://github.com/metasequoiaime/MSIME-Apple/commit/c28859267255d8313f81e4418d23787f5daaa8ac))
* **apple:** keep the engine's helpcode and English paths out of the Apple frontends ([6c90eeb](https://github.com/metasequoiaime/MSIME-Apple/commit/6c90eeb52f023a731489dd2a64683507386f47ca))

## [0.39.2](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.39.1...v0.39.2) (2026-09-05)


### Bug Fixes

* **mac:** repair two engine-bump regressions and restore Sparkle updates ([#223](https://github.com/metasequoiaime/MSIME-Apple/issues/223)) ([30ce66f](https://github.com/metasequoiaime/MSIME-Apple/commit/30ce66f6bb3b753b2c9e180fd1608a4029138c4f))
* **release:** stop referencing secrets from a step condition ([#224](https://github.com/metasequoiaime/MSIME-Apple/issues/224)) ([b450962](https://github.com/metasequoiaime/MSIME-Apple/commit/b450962c274bae8a29c17614134bb4e33da82a04))

## [0.39.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.39.0...v0.39.1) (2026-09-05)


### Bug Fixes

* **mac:** show zero-initial codes and split the helpcode schema notifications ([#220](https://github.com/metasequoiaime/MSIME-Apple/issues/220)) ([aea1b76](https://github.com/metasequoiaime/MSIME-Apple/commit/aea1b76ee6adfb63ea65e5adde626878daef97f0))

## [0.39.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.38.0...v0.39.0) (2026-09-05)


### Features

* **mac:** add native character palette entry ([#209](https://github.com/metasequoiaime/MSIME-Apple/issues/209)) ([7968146](https://github.com/metasequoiaime/MSIME-Apple/commit/796814640375f1e765254d625dcaccdd4ce51e2f))


### Bug Fixes

* **mac:** restore native settings navigation ([#208](https://github.com/metasequoiaime/MSIME-Apple/issues/208)) ([13e821c](https://github.com/metasequoiaime/MSIME-Apple/commit/13e821c01c4b9caaf4e3a00de2ad2a0f77405b4b))

## [0.38.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.37.0...v0.38.0) (2026-09-05)


### Features

* **mac:** add toolbar utility menu ([#207](https://github.com/metasequoiaime/MSIME-Apple/issues/207)) ([cfad9b9](https://github.com/metasequoiaime/MSIME-Apple/commit/cfad9b9993d61beb1427918e2cb1abcc0c74e437))
* **mac:** add traditional Chinese output ([#206](https://github.com/metasequoiaime/MSIME-Apple/issues/206)) ([5c241a8](https://github.com/metasequoiaime/MSIME-Apple/commit/5c241a8190b5a89a4f01f8373b532f8fa2eec52d))

## [0.37.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.36.0...v0.37.0) (2026-09-05)


### Features

* **mac:** add Shuangpin keymap hints ([#203](https://github.com/metasequoiaime/MSIME-Apple/issues/203)) ([c2d0141](https://github.com/metasequoiaime/MSIME-Apple/commit/c2d01411147d85be4302e823e05304688daccacf))

## [0.36.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.35.1...v0.36.0) (2026-09-05)


### Features

* **mac:** add native floating status toolbar ([#205](https://github.com/metasequoiaime/MSIME-Apple/issues/205)) ([3f2686b](https://github.com/metasequoiaime/MSIME-Apple/commit/3f2686b1270a5b9f514b78a7356740608081ee04))

## [0.35.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.35.0...v0.35.1) (2026-09-05)


### Bug Fixes

* **mac:** restore compact settings layout ([#204](https://github.com/metasequoiaime/MSIME-Apple/issues/204)) ([4fcb9b6](https://github.com/metasequoiaime/MSIME-Apple/commit/4fcb9b636236c185d2db868bf8a07d6add4c8f24))

## [0.35.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.34.0...v0.35.0) (2026-09-04)


### Features

* **mac:** surface Wubi settings in scheme card ([#202](https://github.com/metasequoiaime/MSIME-Apple/issues/202)) ([43bee29](https://github.com/metasequoiaime/MSIME-Apple/commit/43bee2947564fe45bd5f4331f3032c9777f4b0fd))

## [0.34.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.33.1...v0.34.0) (2026-09-04)


### Features

* **mac:** show auxiliary codes in candidates ([#201](https://github.com/metasequoiaime/MSIME-Apple/issues/201)) ([47fecc8](https://github.com/metasequoiaime/MSIME-Apple/commit/47fecc85d4c9ae086ae744173e4189bcc49f0511))

## [0.33.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.33.0...v0.33.1) (2026-09-04)


### Bug Fixes

* **mac:** scope installer process shutdown ([3891752](https://github.com/metasequoiaime/MSIME-Apple/commit/389175231240121b6dfa7ac30b3747f8e81390a3))
* **mac:** scope uninstaller process shutdown ([5297ab7](https://github.com/metasequoiaime/MSIME-Apple/commit/5297ab73825bd51392763e7323fe79afbbf59d29))

## [0.33.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.32.0...v0.33.0) (2026-09-04)


### Features

* **mac:** align settings layout with reference design ([#193](https://github.com/metasequoiaime/MSIME-Apple/issues/193)) ([2705e35](https://github.com/metasequoiaime/MSIME-Apple/commit/2705e35bfffa5620d56a0d64e4ecc7c539acb272))


### Bug Fixes

* **mac:** stretch settings rows across cards ([#194](https://github.com/metasequoiaime/MSIME-Apple/issues/194)) ([850a9ed](https://github.com/metasequoiaime/MSIME-Apple/commit/850a9ed886c4f01b612b0121b0aefeace93d50f4))
* **release:** disable unsigned automatic update polling ([#195](https://github.com/metasequoiaime/MSIME-Apple/issues/195)) ([06d0f3c](https://github.com/metasequoiaime/MSIME-Apple/commit/06d0f3cc3989d82b83af6778ec7bedac90585626))
* **release:** retry transient GitHub API failures ([#196](https://github.com/metasequoiaime/MSIME-Apple/issues/196)) ([2462620](https://github.com/metasequoiaime/MSIME-Apple/commit/24626201d1a07baf1215dc5bd4051b9b8e512f27))

## [0.32.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.31.0...v0.32.0) (2026-09-04)


### Features

* **mac:** support full-width input toggle ([#187](https://github.com/metasequoiaime/MSIME-Apple/issues/187)) ([4d2de2b](https://github.com/metasequoiaime/MSIME-Apple/commit/4d2de2b7fd6d29adb9a4005cdb0ce4ed617e64de))


### Bug Fixes

* **mac:** route letters through full-width mode ([#188](https://github.com/metasequoiaime/MSIME-Apple/issues/188)) ([31f7e28](https://github.com/metasequoiaime/MSIME-Apple/commit/31f7e284d9b05d0dbd585d9955808d8044f66713))
* **release:** gate signature verification for unsigned builds ([#191](https://github.com/metasequoiaime/MSIME-Apple/issues/191)) ([1b10b32](https://github.com/metasequoiaime/MSIME-Apple/commit/1b10b3290e69d6454bfa85dbd292e9bd0d7343d3))
* **release:** skip unsigned Sparkle appcast ([#189](https://github.com/metasequoiaime/MSIME-Apple/issues/189)) ([6732c6c](https://github.com/metasequoiaime/MSIME-Apple/commit/6732c6cf59bbccb3ae794b5b549a0327a6a86b98))

## [0.31.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.30.1...v0.31.0) (2026-09-04)


### Features

* **mac:** add updates and feedback settings page ([#179](https://github.com/metasequoiaime/MSIME-Apple/issues/179)) ([3b39c44](https://github.com/metasequoiaime/MSIME-Apple/commit/3b39c440803ad3d2c1ddf7807863f104c7b86679))


### Bug Fixes

* **mac:** auto-enable input source after pkg install ([#182](https://github.com/metasequoiaime/MSIME-Apple/issues/182)) ([c3d79a6](https://github.com/metasequoiaime/MSIME-Apple/commit/c3d79a68cbabbeaf3ca5d5c4b0178e5def6b5a58))
* **mac:** enable input source after development install ([#180](https://github.com/metasequoiaime/MSIME-Apple/issues/180)) ([1a53ff5](https://github.com/metasequoiaime/MSIME-Apple/commit/1a53ff584e525eeaf4a5c8766f214e4b17b68d46))
* **mac:** keep input menu icon visible in dark mode ([#185](https://github.com/metasequoiaime/MSIME-Apple/issues/185)) ([4058dba](https://github.com/metasequoiaime/MSIME-Apple/commit/4058dba386ebf141062128602c7c483c7625deb0))
* **mac:** preserve menu icon retina metadata ([#181](https://github.com/metasequoiaime/MSIME-Apple/issues/181)) ([7a61ff4](https://github.com/metasequoiaime/MSIME-Apple/commit/7a61ff4e8d1ff5b630d375192be383b2a4c67f31))
* **release:** document pkg auto-enable behavior ([#184](https://github.com/metasequoiaime/MSIME-Apple/issues/184)) ([28b154d](https://github.com/metasequoiaime/MSIME-Apple/commit/28b154d1bddb8a92c3538dc23a9c76d4f0462888))

## [0.30.1](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.30.0...v0.30.1) (2026-09-04)


### Bug Fixes

* **mac:** support non-default package build dirs ([#178](https://github.com/metasequoiaime/MSIME-Apple/issues/178)) ([d4326be](https://github.com/metasequoiaime/MSIME-Apple/commit/d4326bee07e2110ca445fd833f7c22576f89efdf))

## [0.30.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.29.0...v0.30.0) (2026-09-04)


### Features

* **mac:** add candidate paging shortcuts ([#177](https://github.com/metasequoiaime/MSIME-Apple/issues/177)) ([586f503](https://github.com/metasequoiaime/MSIME-Apple/commit/586f50344ec1b04b6a5e309c8c60f3a7b522634a))

## [0.29.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.28.0...v0.29.0) (2026-09-04)


### Features

* **mac:** add keyboard input settings and Wubi ([#171](https://github.com/metasequoiaime/MSIME-Apple/issues/171)) ([92ff49d](https://github.com/metasequoiaime/MSIME-Apple/commit/92ff49d69d8fa538590fa0cd0aa9aeb60bcdf2c9))
* **mac:** add live candidate appearance preview ([#173](https://github.com/metasequoiaime/MSIME-Apple/issues/173)) ([43cce5e](https://github.com/metasequoiaime/MSIME-Apple/commit/43cce5ee259b8a98abf993dc2aa401dee7589c6b))
* **mac:** add Wubi behavior settings ([#176](https://github.com/metasequoiaime/MSIME-Apple/issues/176)) ([6dd7532](https://github.com/metasequoiaime/MSIME-Apple/commit/6dd7532b061bf7b8299ad17486ccf4f2b2f95b86))


### Bug Fixes

* **ci:** ignore non-pinyin dictionary indexes ([#174](https://github.com/metasequoiaime/MSIME-Apple/issues/174)) ([77abbe3](https://github.com/metasequoiaime/MSIME-Apple/commit/77abbe3ad8638b28923fb2c49c3b907208da8833))
* **release:** create draft after direct promotion ([#172](https://github.com/metasequoiaime/MSIME-Apple/issues/172)) ([5120fab](https://github.com/metasequoiaime/MSIME-Apple/commit/5120fab08457f36b1ef054727fbba0ad15bbe063))

## [0.28.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.27.0...v0.28.0) (2026-09-04)


### Features

* **ios:** add host input scheme settings ([#168](https://github.com/metasequoiaime/MSIME-Apple/issues/168)) ([78fea6e](https://github.com/metasequoiaime/MSIME-Apple/commit/78fea6e3541f7ff0207a75ab153500ab22a8d6cf))
* **ios:** add system input click feedback ([#165](https://github.com/metasequoiaime/MSIME-Apple/issues/165)) ([aaeedf8](https://github.com/metasequoiaime/MSIME-Apple/commit/aaeedf84ad7cbd896bfb5a0453f0d8c63ed6bb41))
* **ios:** bundle privacy manifests ([#169](https://github.com/metasequoiaime/MSIME-Apple/issues/169)) ([83c8dae](https://github.com/metasequoiaime/MSIME-Apple/commit/83c8dae6aa2a37ebfbb019a7cdbc4dbc32376745))
* **ios:** repeat backspace while held ([#163](https://github.com/metasequoiaime/MSIME-Apple/issues/163)) ([c02a6be](https://github.com/metasequoiaime/MSIME-Apple/commit/c02a6bef369d2716266e655c4fdcffccd82f517a))
* **ios:** share input scheme through app group ([#167](https://github.com/metasequoiaime/MSIME-Apple/issues/167)) ([8704dc5](https://github.com/metasequoiaime/MSIME-Apple/commit/8704dc57675261ac3135d3583e8d6bd6b1b3bc62))


### Bug Fixes

* **ios:** handle missing input traits ([#164](https://github.com/metasequoiaime/MSIME-Apple/issues/164)) ([fbeb07c](https://github.com/metasequoiaime/MSIME-Apple/commit/fbeb07cac6a1bc34795d967fd399585b86afa1ba))
* **ios:** respect the system keyboard height ([#166](https://github.com/metasequoiaime/MSIME-Apple/issues/166)) ([412a956](https://github.com/metasequoiaime/MSIME-Apple/commit/412a956ea30ae5238f6808e04b450f4a46cb41ac))
* **release:** promote validated release commits without PRs ([#170](https://github.com/metasequoiaime/MSIME-Apple/issues/170)) ([51a71ba](https://github.com/metasequoiaime/MSIME-Apple/commit/51a71ba87e1d483cb07cd307252c2d181cfe682a))

## [0.27.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.26.0...v0.27.0) (2026-09-04)


### Features

* **ios:** adapt return key to input traits ([#159](https://github.com/metasequoiaime/MSIME-Apple/issues/159)) ([a3153ad](https://github.com/metasequoiaime/MSIME-Apple/commit/a3153adbc224ae1e55ff9b5207730279bfe32ff2))
* **ios:** follow automatic capitalization traits ([#160](https://github.com/metasequoiaime/MSIME-Apple/issues/160)) ([3d53f89](https://github.com/metasequoiaime/MSIME-Apple/commit/3d53f898a16ea45f45ba6ea46d11610e435e12e7))

## [0.26.0](https://github.com/metasequoiaime/MSIME-Apple/compare/v0.25.0...v0.26.0) (2026-09-04)


### Features

* **ios:** add English shift and caps lock ([#157](https://github.com/metasequoiaime/MSIME-Apple/pull/157)) ([e432e55](https://github.com/metasequoiaime/MSIME-Apple/commit/e432e55aa635225a06c1a0fd52b3fd689b421c1a))
* **ios:** add pinyin scheme switch ([#152](https://github.com/metasequoiaime/MSIME-Apple/pull/152)) ([e626ed7](https://github.com/metasequoiaime/MSIME-Apple/commit/e626ed779735de4cc9571aa7e4ab335d46515915))


### Bug Fixes

* **deps:** use canonical dictionary repository ([#155](https://github.com/metasequoiaime/MSIME-Apple/pull/155)) ([bb417f8](https://github.com/metasequoiaime/MSIME-Apple/commit/bb417f8feaaa61df60b12147784bb87477a8eaf3))
* **ios:** adapt action row to narrow screens ([#150](https://github.com/metasequoiaime/MSIME-Apple/pull/150)) ([33e4c52](https://github.com/metasequoiaime/MSIME-Apple/commit/33e4c5279130e6a68ea6a647285298375f0741c8))
* **ios:** isolate UI tests on main actor ([#156](https://github.com/metasequoiaime/MSIME-Apple/pull/156)) ([47bb395](https://github.com/metasequoiaime/MSIME-Apple/commit/47bb39589dee50b834bd2e85e3aa1cecd9b9346e))
* **ios:** use system input mode menu ([#153](https://github.com/metasequoiaime/MSIME-Apple/pull/153)) ([9985534](https://github.com/metasequoiaime/MSIME-Apple/commit/99855347ae8df9c1808a5dc29ec2822187732702))
* **release:** use canonical Apple repository URLs ([#154](https://github.com/metasequoiaime/MSIME-Apple/pull/154)) ([381af7d](https://github.com/metasequoiaime/MSIME-Apple/commit/381af7db8d78d0b18d2c463afd1ea82da2df820b))

## [0.25.0](https://github.com/houko/MetasequoiaImeApple/compare/v0.24.0...v0.25.0) (2026-09-04)


### Features

* **ios:** add Chinese English mode switch ([#148](https://github.com/houko/MetasequoiaImeApple/issues/148)) ([7404661](https://github.com/houko/MetasequoiaImeApple/commit/740466120bd95c020c3ec2097df8d70fe764c0fd))
* **ios:** add host app and keyboard extension shell ([#141](https://github.com/houko/MetasequoiaImeApple/issues/141)) ([90b5189](https://github.com/houko/MetasequoiaImeApple/commit/90b518965de636931b65414d0787da918decb6ff))
* **ios:** add number and symbol keyboard ([#145](https://github.com/houko/MetasequoiaImeApple/issues/145)) ([400bd77](https://github.com/houko/MetasequoiaImeApple/commit/400bd772fa33388f9a62afaf2a48bc0dc0c20f79))
* **ios:** number candidate chips ([#146](https://github.com/houko/MetasequoiaImeApple/issues/146)) ([6d9e848](https://github.com/houko/MetasequoiaImeApple/commit/6d9e848986f97df98efe1235831d87afc1247697))
* **ios:** package compact pinyin dictionary ([#143](https://github.com/houko/MetasequoiaImeApple/issues/143)) ([63c8093](https://github.com/houko/MetasequoiaImeApple/commit/63c8093fbd74aa8312c146a5d28768a9db87e3d1))
* **ios:** route keyboard through shared engine ([#142](https://github.com/houko/MetasequoiaImeApple/issues/142)) ([575348e](https://github.com/houko/MetasequoiaImeApple/commit/575348e48ff35e01cf73484a12386407732581bd))


### Bug Fixes

* **ios:** route apostrophe through composition ([#147](https://github.com/houko/MetasequoiaImeApple/issues/147)) ([f3caf12](https://github.com/houko/MetasequoiaImeApple/commit/f3caf1290ea9b478a1ff8d542ba215175d22859c))

## [0.24.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.23.2...v0.24.0) (2026-09-04)


### Features

* **updater:** install updates in place ([#137](https://github.com/houko/MetasequoiaImeMac/issues/137)) ([816b1ed](https://github.com/houko/MetasequoiaImeMac/commit/816b1ed6b6c301b231ea61d23d0019f925ecfad5))

## [0.23.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.23.1...v0.23.2) (2026-09-04)


### Bug Fixes

* **ui:** add dedicated input source icon ([#133](https://github.com/houko/MetasequoiaImeMac/issues/133)) ([63c65d6](https://github.com/houko/MetasequoiaImeMac/commit/63c65d64897051259f70dd1ebebe8a1afa521b44))

## [0.23.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.23.0...v0.23.1) (2026-09-04)


### Bug Fixes

* **update:** retry failed checks sooner ([#130](https://github.com/houko/MetasequoiaImeMac/issues/130)) ([b0681e5](https://github.com/houko/MetasequoiaImeMac/commit/b0681e524ad15336d7314a3b53525e4330503c56))

## [0.23.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.22.0...v0.23.0) (2026-09-04)


### Features

* **update:** download recommended release archive ([#128](https://github.com/houko/MetasequoiaImeMac/issues/128)) ([ecc8c9b](https://github.com/houko/MetasequoiaImeMac/commit/ecc8c9b1e53f0683039aa11dfc54cc2df1522709))

## [0.22.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.21.2...v0.22.0) (2026-09-04)


### Features

* **settings:** add standalone launcher ([#126](https://github.com/houko/MetasequoiaImeMac/issues/126)) ([f43e4d8](https://github.com/houko/MetasequoiaImeMac/commit/f43e4d84278349757ab862c23b47877ec5f00afd))

## [0.21.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.21.1...v0.21.2) (2026-09-04)


### Bug Fixes

* **install:** enable registered input source ([#124](https://github.com/houko/MetasequoiaImeMac/issues/124)) ([c1e1611](https://github.com/houko/MetasequoiaImeMac/commit/c1e1611b08302a606ba6f766409a882d429db698))

## [0.21.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.21.0...v0.21.1) (2026-09-04)


### Bug Fixes

* **install:** stop forcing logout after pkg install ([#122](https://github.com/houko/MetasequoiaImeMac/issues/122)) ([f5cadeb](https://github.com/houko/MetasequoiaImeMac/commit/f5cadebb613152f1ccea3f414a0e32297e3b0955))

## [0.21.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.13...v0.21.0) (2026-09-04)


### Features

* **update:** discover new releases ([#120](https://github.com/houko/MetasequoiaImeMac/issues/120)) ([6eaeb16](https://github.com/houko/MetasequoiaImeMac/commit/6eaeb16634c05e3ae0d0d12bc6f7557795f237a8))

## [0.20.13](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.12...v0.20.13) (2026-09-04)


### Bug Fixes

* **install:** register release input source ([#118](https://github.com/houko/MetasequoiaImeMac/issues/118)) ([2f16774](https://github.com/houko/MetasequoiaImeMac/commit/2f167742a09a3ba9d65f7761e64caee4b558c655))

## [0.20.12](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.11...v0.20.12) (2026-09-04)


### Bug Fixes

* **uninstall:** fail closed on process check errors ([#116](https://github.com/houko/MetasequoiaImeMac/issues/116)) ([4c324af](https://github.com/houko/MetasequoiaImeMac/commit/4c324af1ae505a8d8874e5ee33e4f63d7e7be30f))

## [0.20.11](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.10...v0.20.11) (2026-09-03)


### Bug Fixes

* **uninstall:** serialize with installation ([#114](https://github.com/houko/MetasequoiaImeMac/issues/114)) ([59efe20](https://github.com/houko/MetasequoiaImeMac/commit/59efe20c1fc60dad0a25b3e9d0ed6f8d51d7039b))

## [0.20.10](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.9...v0.20.10) (2026-09-03)


### Bug Fixes

* **install:** serialize concurrent upgrades ([#112](https://github.com/houko/MetasequoiaImeMac/issues/112)) ([37ab11b](https://github.com/houko/MetasequoiaImeMac/commit/37ab11bef185432c9f94a69edbb6446d811dfd74))

## [0.20.9](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.8...v0.20.9) (2026-09-03)


### Bug Fixes

* **install:** wait for input method shutdown ([#110](https://github.com/houko/MetasequoiaImeMac/issues/110)) ([278707d](https://github.com/houko/MetasequoiaImeMac/commit/278707d490f4f1a186b5c3da4dad0b814c499423))

## [0.20.8](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.7...v0.20.8) (2026-09-03)


### Bug Fixes

* **install:** clean partial temporary setup ([#108](https://github.com/houko/MetasequoiaImeMac/issues/108)) ([36e1b89](https://github.com/houko/MetasequoiaImeMac/commit/36e1b89575d6b212e48742958f99b4395d127f1a))

## [0.20.7](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.6...v0.20.7) (2026-09-03)


### Bug Fixes

* **dictionary:** verify bundled database fingerprint ([#106](https://github.com/houko/MetasequoiaImeMac/issues/106)) ([b72e920](https://github.com/houko/MetasequoiaImeMac/commit/b72e9201972c595ae4d4f9b952693926888f13d3))

## [0.20.6](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.5...v0.20.6) (2026-09-03)


### Bug Fixes

* **dictionary:** validate bundled database before upgrade ([#104](https://github.com/houko/MetasequoiaImeMac/issues/104)) ([e9dc8e9](https://github.com/houko/MetasequoiaImeMac/commit/e9dc8e94d3648f96955f3345c046a349d1d3c0ee))

## [0.20.5](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.4...v0.20.5) (2026-09-03)


### Bug Fixes

* **uninstall:** reject unsafe home directories ([#102](https://github.com/houko/MetasequoiaImeMac/issues/102)) ([337e6d8](https://github.com/houko/MetasequoiaImeMac/commit/337e6d83acbb9617310b8d4702a8593635df6a6f))

## [0.20.4](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.3...v0.20.4) (2026-09-03)


### Bug Fixes

* **install:** reject unsafe home directories ([#100](https://github.com/houko/MetasequoiaImeMac/issues/100)) ([0ce9655](https://github.com/houko/MetasequoiaImeMac/commit/0ce9655250c6e61459dde7c4bbe513aaa2d94b05))

## [0.20.3](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.2...v0.20.3) (2026-09-03)


### Bug Fixes

* **settings:** restore evolving defaults ([#98](https://github.com/houko/MetasequoiaImeMac/issues/98)) ([4ffe027](https://github.com/houko/MetasequoiaImeMac/commit/4ffe027b0050f01e0b507f11edb7356523886426))

## [0.20.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.1...v0.20.2) (2026-09-03)


### Bug Fixes

* **release:** verify artifacts before publishing ([#96](https://github.com/houko/MetasequoiaImeMac/issues/96)) ([3d4ae70](https://github.com/houko/MetasequoiaImeMac/commit/3d4ae70e619e461e52400207f78bd065835a89b6))

## [0.20.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.20.0...v0.20.1) (2026-09-03)


### Bug Fixes

* **release:** keep uninstaller after pkg install ([#94](https://github.com/houko/MetasequoiaImeMac/issues/94)) ([a1c95ca](https://github.com/houko/MetasequoiaImeMac/commit/a1c95cabcced14fc9b3355c063130475a287820b))

## [0.20.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.7...v0.20.0) (2026-09-03)


### Features

* **release:** add recoverable uninstall workflow ([#90](https://github.com/houko/MetasequoiaImeMac/issues/90)) ([7fe823c](https://github.com/houko/MetasequoiaImeMac/commit/7fe823c5bc989f050a099e3cb64b503fb34c244b))

## [0.19.7](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.6...v0.19.7) (2026-09-03)


### Bug Fixes

* **installer:** preserve previous bundle during rollback ([#85](https://github.com/houko/MetasequoiaImeMac/issues/85)) ([fc353b9](https://github.com/houko/MetasequoiaImeMac/commit/fc353b99129d7e2d8c4c613da218bd3bd7a0357f))

## [0.19.6](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.5...v0.19.6) (2026-09-03)


### Bug Fixes

* **release:** preserve assets on packaging failure ([#83](https://github.com/houko/MetasequoiaImeMac/issues/83)) ([cfa43a6](https://github.com/houko/MetasequoiaImeMac/commit/cfa43a6aba44ef9afa94800ac9e0259caf9f44d2))

## [0.19.5](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.4...v0.19.5) (2026-09-03)


### Bug Fixes

* **release:** label unsigned installer internally ([#81](https://github.com/houko/MetasequoiaImeMac/issues/81)) ([a9bcfd2](https://github.com/houko/MetasequoiaImeMac/commit/a9bcfd24172041152ea0e15c4a5676f6c4ada804))

## [0.19.4](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.3...v0.19.4) (2026-09-03)


### Bug Fixes

* **input:** stop swallowing rejected characters ([#78](https://github.com/houko/MetasequoiaImeMac/issues/78)) ([4f2de4c](https://github.com/houko/MetasequoiaImeMac/commit/4f2de4c15213f05eb3f614b08b72f0b5aef5b267))

## [0.19.3](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.2...v0.19.3) (2026-09-03)


### Bug Fixes

* **input:** tolerate invalid candidate text ([#76](https://github.com/houko/MetasequoiaImeMac/issues/76)) ([c670839](https://github.com/houko/MetasequoiaImeMac/commit/c670839c81687de4f1aebc6bd524801feae12e81))

## [0.19.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.1...v0.19.2) (2026-09-03)


### Bug Fixes

* **release:** package legacy drafts safely ([#74](https://github.com/houko/MetasequoiaImeMac/issues/74)) ([83a8420](https://github.com/houko/MetasequoiaImeMac/commit/83a8420783a93a71c97f43fd7ae5f6b82f5af21c))

## [0.19.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.19.0...v0.19.1) (2026-09-03)


### Bug Fixes

* **release:** publish unsigned fallback ([#72](https://github.com/houko/MetasequoiaImeMac/issues/72)) ([36974b7](https://github.com/houko/MetasequoiaImeMac/commit/36974b760fb274f8f3af200f010fef1b736ae1d9))

## [0.19.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.18.0...v0.19.0) (2026-09-03)


### Features

* **settings:** clear learned data ([#70](https://github.com/houko/MetasequoiaImeMac/issues/70)) ([8ef0c3f](https://github.com/houko/MetasequoiaImeMac/commit/8ef0c3f51b7fc46f27976e9dbf5b97e15721212f))

## [0.18.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.17.0...v0.18.0) (2026-09-03)


### Features

* **dictionary:** reset learned data safely ([#68](https://github.com/houko/MetasequoiaImeMac/issues/68)) ([d0ab07d](https://github.com/houko/MetasequoiaImeMac/commit/d0ab07dbf194c90d51a7f7b1945c86ac91248eeb))

## [0.17.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.16.0...v0.17.0) (2026-09-03)


### Features

* **settings:** configure input mode shortcut ([#66](https://github.com/houko/MetasequoiaImeMac/issues/66)) ([00e06a2](https://github.com/houko/MetasequoiaImeMac/commit/00e06a2d0a679f7d108811c0170d18391c765292))

## [0.16.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.15.0...v0.16.0) (2026-09-03)


### Features

* **settings:** configure candidate font size ([#64](https://github.com/houko/MetasequoiaImeMac/issues/64)) ([78f4deb](https://github.com/houko/MetasequoiaImeMac/commit/78f4deb4dd912822cb004f729f8bba4c74032360))

## [0.15.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.14.0...v0.15.0) (2026-09-03)


### Features

* **input:** switch between Chinese and English ([#62](https://github.com/houko/MetasequoiaImeMac/issues/62)) ([db5d105](https://github.com/houko/MetasequoiaImeMac/commit/db5d105275fad0c1670fa29c8512c053e54b024f))

## [0.14.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.13.0...v0.14.0) (2026-09-03)


### Features

* **settings:** control candidate learning ([#60](https://github.com/houko/MetasequoiaImeMac/issues/60)) ([0353f29](https://github.com/houko/MetasequoiaImeMac/commit/0353f29c1cafdceee7965e80f64a024b7e016f65))

## [0.13.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.12.0...v0.13.0) (2026-09-03)


### Features

* **settings:** configure candidate page size ([#58](https://github.com/houko/MetasequoiaImeMac/issues/58)) ([a78b32d](https://github.com/houko/MetasequoiaImeMac/commit/a78b32d4ed9a82dbf402103c9b4122c1900aee4e))

## [0.12.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.11.0...v0.12.0) (2026-09-03)


### Features

* **settings:** choose candidate window layout ([#56](https://github.com/houko/MetasequoiaImeMac/issues/56)) ([0f1f313](https://github.com/houko/MetasequoiaImeMac/commit/0f1f3136c84393cd5ca052011771e164f6435fbe))

## [0.11.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.10.1...v0.11.0) (2026-09-03)


### Features

* **settings:** add input menu settings shortcut ([#54](https://github.com/houko/MetasequoiaImeMac/issues/54)) ([a184428](https://github.com/houko/MetasequoiaImeMac/commit/a1844283872c930f5b193d36ec074c19747a2ac7))

## [0.10.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.10.0...v0.10.1) (2026-09-03)


### Bug Fixes

* **input:** navigate candidate pages reliably ([#52](https://github.com/houko/MetasequoiaImeMac/issues/52)) ([e0b4808](https://github.com/houko/MetasequoiaImeMac/commit/e0b4808cd85d3b79e30f579ff95145d99b50d5f1))

## [0.10.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.9.4...v0.10.0) (2026-09-03)


### Features

* **settings:** give preferences a native product layout ([#50](https://github.com/houko/MetasequoiaImeMac/issues/50)) ([d6e0bbb](https://github.com/houko/MetasequoiaImeMac/commit/d6e0bbb90be38b61186bf309dbcf1b4c03bebb7a))

## [0.9.4](https://github.com/houko/MetasequoiaImeMac/compare/v0.9.3...v0.9.4) (2026-09-03)


### Bug Fixes

* **settings:** apply preferences on the next input ([#48](https://github.com/houko/MetasequoiaImeMac/issues/48)) ([26a222f](https://github.com/houko/MetasequoiaImeMac/commit/26a222fe1258ef0f9a1cb237dcb7d6e2860165bf))

## [0.9.3](https://github.com/houko/MetasequoiaImeMac/compare/v0.9.2...v0.9.3) (2026-09-03)


### Bug Fixes

* **input:** map candidate numbers to the visible page ([#46](https://github.com/houko/MetasequoiaImeMac/issues/46)) ([b109eef](https://github.com/houko/MetasequoiaImeMac/commit/b109eef41ab3c7822562989623540a6e48d6a7cc))

## [0.9.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.9.1...v0.9.2) (2026-09-03)


### Bug Fixes

* **input:** commit the highlighted candidate with space ([#44](https://github.com/houko/MetasequoiaImeMac/issues/44)) ([e03d9b1](https://github.com/houko/MetasequoiaImeMac/commit/e03d9b13f5697cb8416fbf3f80cd54484cfbf1e9))

## [0.9.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.9.0...v0.9.1) (2026-09-03)


### Bug Fixes

* **input:** route candidate command keys reliably ([#42](https://github.com/houko/MetasequoiaImeMac/issues/42)) ([0ef1e2e](https://github.com/houko/MetasequoiaImeMac/commit/0ef1e2e75c6467174c99ccbc8a4aa8d8607d310c))

## [0.9.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.8.0...v0.9.0) (2026-09-03)


### Features

* **settings:** show dictionary health ([aec4cfc](https://github.com/houko/MetasequoiaImeMac/commit/aec4cfce7796e70ba01bdbdec3995ba967adb489))


### Bug Fixes

* **release:** run automation with bash ([69b0a5a](https://github.com/houko/MetasequoiaImeMac/commit/69b0a5a49e1588a771f8c9ee4a62a9ff652615aa))

## [0.8.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.7.3...v0.8.0) (2026-09-03)


### Features

* **ui:** add input source icon ([0dbb0f3](https://github.com/houko/MetasequoiaImeMac/commit/0dbb0f340ab3790bba6b4b9ff0f31778aae6f344))

## [0.7.3](https://github.com/houko/MetasequoiaImeMac/compare/v0.7.2...v0.7.3) (2026-09-03)


### Bug Fixes

* **input:** preserve shifted key characters ([80f0dc8](https://github.com/houko/MetasequoiaImeMac/commit/80f0dc8bb44f1f08baa985691afac05675f68f0a))

## [0.7.2](https://github.com/houko/MetasequoiaImeMac/compare/v0.7.1...v0.7.2) (2026-09-03)


### Bug Fixes

* **input:** preserve candidate panel on recovery ([a9ddf4f](https://github.com/houko/MetasequoiaImeMac/commit/a9ddf4f2b764f6763d54a5b2e04092409604679e))

## [0.7.1](https://github.com/houko/MetasequoiaImeMac/compare/v0.7.0...v0.7.1) (2026-09-03)


### Bug Fixes

* **dictionary:** fall back to validated database ([c0f445b](https://github.com/houko/MetasequoiaImeMac/commit/c0f445bc4b12737680a56435d0f67e2e92257869))

## [0.7.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.6.0...v0.7.0) (2026-09-03)


### Features

* **settings:** add reset and version details ([2612c39](https://github.com/houko/MetasequoiaImeMac/commit/2612c39df4a5782a588fb839c0a98239ca369bf4))

## [0.6.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.5.0...v0.6.0) (2026-09-03)


### Features

* **input:** expand Chinese punctuation ([377f7fb](https://github.com/houko/MetasequoiaImeMac/commit/377f7fb1509db6aaf3b1935231bbe1163545606a))
* **input:** learn selected candidates ([b23fc5a](https://github.com/houko/MetasequoiaImeMac/commit/b23fc5a2d3f7139feb4f15c482017c8ccd488dcc))
* **input:** support Chinese punctuation ([066b915](https://github.com/houko/MetasequoiaImeMac/commit/066b915c1149f853ce02062d2ae7b631a7e82f75))
* **input:** support numbered candidate selection ([003c565](https://github.com/houko/MetasequoiaImeMac/commit/003c56509e3e85d99bae19a8d35598c78a361859))
* **release:** require signed notarized artifacts ([f404125](https://github.com/houko/MetasequoiaImeMac/commit/f4041252d4ab62928500e7fc533500f2554ce958))
* **settings:** refresh preferences on activation ([e7462b8](https://github.com/houko/MetasequoiaImeMac/commit/e7462b8cf774e8e50d9aaaad2e71f01d2333a1b8))


### Bug Fixes

* **dictionary:** preserve user data during upgrades ([78b6a24](https://github.com/houko/MetasequoiaImeMac/commit/78b6a243cf26eba4b7f05e187a498507d810acce))
* **input:** commit candidate when composition ends ([b088d94](https://github.com/houko/MetasequoiaImeMac/commit/b088d94c65b5160a24b28048a3e8d41c984256a3))
* **input:** pass through uppercase letters ([34cad90](https://github.com/houko/MetasequoiaImeMac/commit/34cad90737696fd58d9a427de7b808eb053051da))
* **install:** make user install atomic ([3f7f4e1](https://github.com/houko/MetasequoiaImeMac/commit/3f7f4e1a58c27951969e9cc95370f3ddb0112567))
* **release:** enforce Gatekeeper validation ([558f28d](https://github.com/houko/MetasequoiaImeMac/commit/558f28dce7243a9e115823924ce5759b33403c7d))

## [0.5.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.4.0...v0.5.0) (2026-09-03)


### Features

* **settings:** add auxiliary code option ([dcd68e9](https://github.com/houko/MetasequoiaImeMac/commit/dcd68e97f25ef412adf2c006cda2cab59a3a4343))
* **settings:** add pinyin autocorrect option ([b1b3810](https://github.com/houko/MetasequoiaImeMac/commit/b1b3810654f4fe2f228b8f31e1f398c7b4650b3b))

## [0.4.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.3.0...v0.4.0) (2026-09-03)


### Features

* **settings:** support selectable input schemes ([ab566d3](https://github.com/houko/MetasequoiaImeMac/commit/ab566d30bbb3cfe952ed1acf8497362f1b8f0163))

## [0.3.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.2.0...v0.3.0) (2026-09-03)


### Features

* **release:** publish macOS installer package ([c8d524f](https://github.com/houko/MetasequoiaImeMac/commit/c8d524fcc94c42c525ecb6493c25a2fa537dda7d))
* **settings:** add macOS input method preferences panel ([ec8da28](https://github.com/houko/MetasequoiaImeMac/commit/ec8da289ebd3ecfbda179ebf0c13e1029dfa429f))

## [0.2.0](https://github.com/houko/MetasequoiaImeMac/compare/v0.1.0...v0.2.0) (2026-09-03)


### Features

* add native macOS input method ([#1](https://github.com/houko/MetasequoiaImeMac/issues/1)) ([9b47a77](https://github.com/houko/MetasequoiaImeMac/commit/9b47a77ce26701db705e9805ca4b51dc5bf0cc93))


### Bug Fixes

* **release:** use unprefixed version tags ([#3](https://github.com/houko/MetasequoiaImeMac/issues/3)) ([d50861f](https://github.com/houko/MetasequoiaImeMac/commit/d50861fc25c33bf9d18341ef327c99469910981e))
