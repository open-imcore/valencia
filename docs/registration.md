# IDS Registration
## Pub/Pri Generation
- kSecAttrKeyType: kSecAttrKeyTypeRSA
- kSecAttrIsPermanent: kCFBooleanFalse
## Signature generation
- Use the key generated above
- Algorithm is kSecKeyAlgorithmRSASignatureMessagePKCS1v15SHA1
- Data is the data encoding of `KeyVerificationData` using encoding 0x4

