# Third-Party Licenses

Tunnels uses the following open-source libraries. Full license texts are
preserved with each dependency in the source distribution.

| Library | License | Copyright | Repository |
|---|---|---|---|
| [Citadel](https://github.com/orlandos-nl/Citadel) | MIT | © 2022 Orlandos | swift SSH client |
| [BigInt](https://github.com/attaswift/BigInt) | MIT | © 2016-2017 Károly Lőrentey | arbitrary-precision integers |
| [swift-nio](https://github.com/apple/swift-nio) | Apache-2.0 | © Apple Inc. | event-driven network framework |
| [swift-nio-ssh](https://github.com/apple/swift-nio-ssh) | Apache-2.0 | © Apple Inc. | SSH protocol implementation |
| [swift-crypto](https://github.com/apple/swift-crypto) | Apache-2.0 | © Apple Inc. | cryptographic primitives |
| [swift-asn1](https://github.com/apple/swift-asn1) | Apache-2.0 | © Apple Inc. | ASN.1 encoding |
| [swift-atomics](https://github.com/apple/swift-atomics) | Apache-2.0 | © Apple Inc. | low-level atomic operations |
| [swift-collections](https://github.com/apple/swift-collections) | Apache-2.0 | © Apple Inc. | additional collection types |
| [swift-log](https://github.com/apple/swift-log) | Apache-2.0 | © Apple Inc. | logging API |
| [swift-system](https://github.com/apple/swift-system) | Apache-2.0 | © Apple Inc. | system call wrappers |

---

## License Summaries

### MIT License

Permits commercial use, modification, distribution, private use.
Requires preservation of copyright and license notice.

Full text: see [LICENSE](LICENSE) for the Tunnels project itself;
upstream MIT projects ship their own LICENSE files in the source archive.

### Apache License 2.0

Same permissions as MIT, plus:

- **Patent grant**: contributors grant a license to any patents they hold
  covering the contribution.
- **Trademark restriction**: cannot use the contributors' names, logos, or
  trademarks except for descriptive attribution.
- **State changes**: derivative works must clearly mark any modifications
  made to the original code.

Full text: https://www.apache.org/licenses/LICENSE-2.0

---

## How to view full license texts

Each dependency ships its own `LICENSE` and (for Apache-2.0 projects) `NOTICE`
file at the root of its source tree. When you resolve SPM packages locally,
they appear under:

```
build/DerivedData/SourcePackages/checkouts/<package>/LICENSE*
```

For convenience, key license texts are also bundled inside the app at runtime
(see **Settings → Acknowledgements** in the application menu).

---

If you believe an attribution is missing or incorrect, please open an issue.
