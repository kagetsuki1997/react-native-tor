const path = require('path');
// const pak = require('../package.json');

module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['module:metro-react-native-babel-preset'],
    plugins: [
      // [
      //   'module-resolver',
      //   {
      //     alias: {
      //       [pak.name]: path.join(__dirname, '..', pak.source),
      //     },
      //   },
      // ],
    ],
  }
};
