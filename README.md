# GGEsim

An application to convert Giffgaff SIM cards to eSIM.

English | [简体中文](README_zh-CN.md)

## Project Overview

GGEsim is an application that helps users convert their physical Giffgaff SIM cards to eSIM. This project aims to simplify the process of obtaining and using eSIM for Giffgaff card users who don't have eSIM-compatible phones.

Here are some screenshots of the GGEsim application:

![Screenshot 1](screenshots/screenshot1.png)

## Features

- Sign in with Giffgaff OAuth and PKCE, with persisted tokens, automatic refresh,
  and one retry after an unauthorized response
- Convert a physical Giffgaff SIM to eSIM through SMS MFA and SIM swap during
  the supported London service window
- Order a new eSIM for an account without a SIM, manage saved payment methods,
  and complete activation through Giffgaff's authenticated web checkout
- Display the eSIM download QR code and LPA string
- Export diagnostic logs, open the usage guide, and report network failures
- Equivalent iOS and Android clients

## Android setup

Open `Android-Client` in Android Studio. Add `GGESIM_CLIENT_ID` and
`GGESIM_CLIENT_SECRET` to `Android-Client/local.properties`, using
`Android-Client/local.properties.example` as the template. The Android client
uses the same Giffgaff OAuth, SIM swap, new eSIM ordering, payment, and QR-code
flows as the iOS client. Command-line builds require JDK 17 or newer; Android
Studio's bundled runtime is supported. `GGESIM_GUIDE_URL` is optional and
defaults to the usage guide below.

With an emulator or device connected, run the complete local verification with:

```shell
./gradlew testDebugUnitTest connectedDebugAndroidTest lintDebug assembleRelease
```

## Usage Instructions

Please refer to this document for usage instructions: https://shuzimumin.com/t/topic/102

## Contribution Guidelines

We welcome contributions from the community to the GGEsim project. If you have any suggestions for improvements or find any bugs, please submit an issue or pull request.
If you have features that need to be discussed, you can also reply to the author in the post linked above.

## License

This project is licensed under the MIT License. For more details, please see the [LICENSE](LICENSE) file.
