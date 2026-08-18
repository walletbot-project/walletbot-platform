// Currency catalog — single source of truth for backend validation and the
// web app (apps/web/src/lib/currencies.ts re-exports this). The native app
// (apps/native/lib/screens/create_account.dart) keeps its own Dart copy in
// sync manually since it can't import TS.
export const CURRENCIES: readonly { code: string; name: string }[] = [
    { code: 'AED', name: 'Dírham emiratí' },
    { code: 'ARS', name: 'Peso argentino' },
    { code: 'AUD', name: 'Dólar australiano' },
    { code: 'BOB', name: 'Boliviano' },
    { code: 'BRL', name: 'Real brasileño' },
    { code: 'CAD', name: 'Dólar canadiense' },
    { code: 'CHF', name: 'Franco suizo' },
    { code: 'CLP', name: 'Peso chileno' },
    { code: 'CNY', name: 'Yuan chino' },
    { code: 'COP', name: 'Peso colombiano' },
    { code: 'CRC', name: 'Colón costarricense' },
    { code: 'CUP', name: 'Peso cubano' },
    { code: 'DKK', name: 'Corona danesa' },
    { code: 'DOP', name: 'Peso dominicano' },
    { code: 'EGP', name: 'Libra egipcia' },
    { code: 'EUR', name: 'Euro' },
    { code: 'GBP', name: 'Libra esterlina' },
    { code: 'GTQ', name: 'Quetzal guatemalteco' },
    { code: 'HKD', name: 'Dólar de Hong Kong' },
    { code: 'HNL', name: 'Lempira hondureño' },
    { code: 'HUF', name: 'Forinto húngaro' },
    { code: 'IDR', name: 'Rupia indonesia' },
    { code: 'ILS', name: 'Séquel israelí' },
    { code: 'INR', name: 'Rupia india' },
    { code: 'JPY', name: 'Yen japonés' },
    { code: 'KRW', name: 'Won surcoreano' },
    { code: 'MXN', name: 'Peso mexicano' },
    { code: 'MYR', name: 'Ringgit malayo' },
    { code: 'NGN', name: 'Naira nigeriana' },
    { code: 'NIO', name: 'Córdoba nicaragüense' },
    { code: 'NOK', name: 'Corona noruega' },
    { code: 'NZD', name: 'Dólar neozelandés' },
    { code: 'PAB', name: 'Balboa panameño' },
    { code: 'PEN', name: 'Sol peruano' },
    { code: 'PHP', name: 'Peso filipino' },
    { code: 'PKR', name: 'Rupia pakistaní' },
    { code: 'PLN', name: 'Esloti polaco' },
    { code: 'PYG', name: 'Guaraní paraguayo' },
    { code: 'RON', name: 'Leu rumano' },
    { code: 'RUB', name: 'Rublo ruso' },
    { code: 'SAR', name: 'Riyal saudí' },
    { code: 'SEK', name: 'Corona sueca' },
    { code: 'SGD', name: 'Dólar singapurense' },
    { code: 'THB', name: 'Baht tailandés' },
    { code: 'TRY', name: 'Lira turca' },
    { code: 'TWD', name: 'Nuevo dólar taiwanés' },
    { code: 'UAH', name: 'Grivna ucraniana' },
    { code: 'USD', name: 'Dólar estadounidense' },
    { code: 'UYU', name: 'Peso uruguayo' },
    { code: 'VES', name: 'Bolívar venezolano' },
    { code: 'VND', name: 'Dong vietnamita' },
    { code: 'ZAR', name: 'Rand sudafricano' },
]

export const SUGGESTED_CURRENCIES = ['ARS', 'USD', 'EUR', 'BRL'] as const

export const DEFAULT_CURRENCY = 'ARS'

const CURRENCY_CODES = new Set(CURRENCIES.map((c) => c.code))

export function isValidCurrencyCode(code: string): boolean {
    return CURRENCY_CODES.has(code)
}
