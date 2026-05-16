import { exportJWK, exportPKCS8, generateKeyPair } from 'jose'

const { publicKey, privateKey } = await generateKeyPair('RS256', {
    modulusLength: 2048,
    extractable: true,
})

const pkcs8 = await exportPKCS8(privateKey)
const jwk = await exportJWK(publicKey)
jwk.use = 'sig'
jwk.alg = 'RS256'
jwk.kid = `wb-${Math.random().toString(36).slice(2, 10)}`

const jwks = { keys: [jwk] }

console.log('---JWT_PRIVATE_KEY---')
console.log(pkcs8.trim())
console.log('---JWKS---')
console.log(JSON.stringify(jwks))
console.log('---KID---')
console.log(jwk.kid)
