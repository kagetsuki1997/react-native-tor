// This might be removed when this issue is fixed: https://github.com/Sifir-io/react-native-tor/issues/57

import compressing from 'compressing';
import fs from 'fs';

console.log('Removing unsupported arm64 JNI from sifir_android');

(async () => {
    await compressing.zip.uncompress(
        './android/libs/sifir_android.aar',
        './android/libs/sifir_android'
    );

    fs.rmSync(
        './android/libs/sifir_android/jni/arm64',
        { force: true, recursive: true }
    );

    fs.rmSync('./android/libs/sifir_android.aar');

    await compressing.zip.compressDir(
        './android/libs/sifir_android',
        './android/libs/sifir_android.aar',
        { ignoreBase: true }
    );

    fs.rmSync('./android/libs/sifir_android', {
        force: true,
        recursive: true
    });
})();