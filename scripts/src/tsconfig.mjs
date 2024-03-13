{
  "compilerOptions": {
    "target": "ES6", // Specify the target ECMAScript version
    "module": "ESNext", // Specify the module system (ESM)
    "outDir": "./dist", // Specify the output directory for compiled JavaScript files
    "strict": true, // Enable strict type-checking options
    "esModuleInterop": true, // Enable interoperability between ESM and CommonJS
    "skipLibCheck": true, // Skip type checking of declaration files
    "forceConsistentCasingInFileNames": true // Ensure consistent casing in file names
  },
  "include": ["**/*.ts"], // Specify the files to be included in compilation
  "exclude": ["node_modules"] // Specify files/folders to be excluded from compilation
}
