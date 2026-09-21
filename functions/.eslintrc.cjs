module.exports = {
  root: true,
  env: { es2022: true, node: true, mocha: true },
  parser: '@typescript-eslint/parser',
  parserOptions: { project: './tsconfig.json', sourceType: 'module' },
  plugins: ['@typescript-eslint'],
  extends: ['eslint:recommended', 'plugin:@typescript-eslint/recommended'],
  ignorePatterns: ['lib/**'],
  rules: {
    'max-len': 'off',
    '@typescript-eslint/no-explicit-any': 'off'
  }
};
