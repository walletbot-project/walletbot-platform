/**
 * The usability-session protocol from docs/sesiones-usabilidad.md: the script
 * the conductor reads, the observation sheet the companion fills, and the
 * rules the backend uses to validate every field written to it.
 *
 * The text stays in Spanish whatever the UI language is, because it is what
 * gets read aloud to participants. Only the backoffice chrome around it goes
 * through the web i18n catalogs.
 */

export const USABILITY_SCENARIOS = [0, 1, 2] as const
export type UsabilityScenario = (typeof USABILITY_SCENARIOS)[number]

export const USABILITY_GROUPS = [1, 2] as const
export type UsabilityGroup = (typeof USABILITY_GROUPS)[number]

export type UsabilityChoiceOption = { value: string; label: string }

export type UsabilityFieldKind =
    | { kind: 'text' }
    | { kind: 'longText' }
    | { kind: 'scale'; hints?: readonly string[] }
    | { kind: 'yesNo' }
    | { kind: 'check' }
    | { kind: 'timestamp' }
    | { kind: 'choice'; options: readonly UsabilityChoiceOption[] }
    | { kind: 'multi'; options: readonly UsabilityChoiceOption[] }

export type UsabilityField = UsabilityFieldKind & {
    key: string
    label: string
    hint?: string
}

export type UsabilityRow = {
    id: string
    title: string
    /** Shown under the title, for what the observer expects to see. */
    detail?: string
    /** Scenario 2 question whose expected answer comes from the dataset. */
    answer?: number
    fields: readonly UsabilityField[]
}

export type UsabilityMaterial =
    | { kind: 'list'; title: string; items: readonly string[] }
    | {
          kind: 'table'
          title: string
          notes?: readonly string[]
          columns: readonly string[]
          rows: readonly (readonly string[])[]
          total?: readonly string[]
          footer?: string
          /** Column indexes that hold amounts, aligned to the end. */
          amountColumns?: readonly number[]
      }

export type UsabilityBlock =
    | { type: 'say'; title?: string; paragraphs: readonly string[] }
    | { type: 'note'; text: string }
    | { type: 'list'; title: string; items: readonly string[] }
    | { type: 'fields'; title?: string; fields: readonly UsabilityField[] }
    | { type: 'checklist'; title: string; fields: readonly UsabilityField[] }
    | {
          type: 'material'
          title: string
          materials: readonly UsabilityMaterial[]
      }
    | {
          type: 'rows'
          title: string
          /** First column header of the printed observation sheet. */
          rowHeader: string
          legend?: string
          rows: readonly UsabilityRow[]
      }
    | { type: 'credentials'; scenario: UsabilityScenario }
    | { type: 'scenarioTimer'; scenario: UsabilityScenario }
    | { type: 'sessionTimer'; action: 'start' | 'end' }
    | { type: 'sus' }
    | { type: 'summary' }
    | { type: 'recording' }

export type UsabilityStep = {
    id: string
    title: string
    blocks: readonly UsabilityBlock[]
}

export const USABILITY_TEXT_MAX_LENGTH = 500
export const USABILITY_LONG_TEXT_MAX_LENGTH = 5000

export const SESSION_START_KEY = 'sesion.inicio'
export const SESSION_END_KEY = 'sesion.fin'

export function scenarioStartKey(scenario: UsabilityScenario): string {
    return `e${scenario}.inicio`
}

export function scenarioEndKey(scenario: UsabilityScenario): string {
    return `e${scenario}.fin`
}

export function scenarioDifficultyKey(scenario: UsabilityScenario): string {
    return `e${scenario}.dificultad`
}

const PATH_OPTIONS: readonly UsabilityChoiceOption[] = [
    { value: 'M', label: 'M formulario manual' },
    { value: 'T', label: 'T asistente por texto' },
    { value: 'A', label: 'A nota de voz' },
    { value: 'V', label: 'V modo en vivo' },
]

const METHOD_OPTIONS: readonly UsabilityChoiceOption[] = [
    { value: 'N', label: 'N navegación y filtros' },
    { value: 'T', label: 'T asistente por texto' },
    { value: 'A', label: 'A nota de voz' },
    { value: 'V', label: 'V modo en vivo' },
]

const DOUBT_OPTIONS: readonly UsabilityChoiceOption[] = [
    { value: 'ninguna', label: 'Ninguna' },
    { value: 'pocas', label: 'Pocas' },
    { value: 'muchas', label: 'Muchas' },
]

const DIFFICULTY_HINTS = ['1 muy difícil', '5 muy fácil'] as const

function closingQuestions(scenario: UsabilityScenario): UsabilityBlock {
    return {
        type: 'fields',
        title: 'Al terminar',
        fields: [
            {
                key: scenarioDifficultyKey(scenario),
                kind: 'scale',
                label: 'Del 1 al 5, ¿qué tan fácil o difícil te resultó? 1 es muy difícil y 5 es muy fácil.',
                hints: DIFFICULTY_HINTS,
            },
            {
                key: `e${scenario}.cambiarias`,
                kind: 'longText',
                label: '¿Qué cambiarías de lo que acabás de hacer?',
            },
        ],
    }
}

function notesBlock(stepId: string): UsabilityBlock {
    return {
        type: 'fields',
        fields: [
            {
                key: `${stepId}.notas`,
                kind: 'longText',
                label: 'Notas y frases textuales',
            },
        ],
    }
}

export const SCENARIO_0_EXPENSE_LIST: UsabilityMaterial = {
    kind: 'list',
    title: 'Gastos de la semana',
    items: [
        'Verdulería, hoy, $ 8.500, efectivo',
        'Taxi, hace 3 días, $ 12.000, efectivo',
        'Café con amigos, ayer, $ 9.800, MercadoPago',
        'Factura de luz, hace 5 días, $ 38.400, MercadoPago',
        'Farmacia, hace 2 días, $ 21.300, tarjeta',
        'Zapatillas, hoy, $ 120.000 en 3 cuotas de $ 40.000, tarjeta',
        'Pagué el resumen de la tarjeta desde MercadoPago, ayer, $ 250.000',
    ],
}

export const SCENARIO_1_STATEMENT: UsabilityMaterial = {
    kind: 'table',
    title: 'Banco Ejemplo, Visa terminada en 4821',
    notes: [
        'Período: 25/08/2026 al 24/09/2026. Cierre: 24/09/2026. Vencimiento: 06/10/2026.',
    ],
    columns: ['Fecha', 'Detalle', 'Cuota', 'Pesos', 'Dólares'],
    rows: [
        ['27/08', 'COTO SUC 125', '', '64.320,00', ''],
        ['02/09', 'YPF FULL PALERMO', '', '45.000,00', ''],
        ['05/09', 'AMAZON MKTPLACE', '', '', '42,50'],
        ['08/09', 'MERCADOLIBRE*TIENDA', '', '22.900,00', ''],
        ['10/09', 'FARMACITY 089', '', '18.750,00', ''],
        ['14/09', 'FRAVEGA', '03/06', '85.000,00', ''],
        ['15/09', 'ZARA ALTO PALERMO', '02/03', '30.000,00', ''],
        ['16/09', 'NETFLIX.COM', '', '', '12,99'],
        ['18/09', 'DEV. MERCADOLIBRE*TIENDA', '', '-22.900,00', ''],
        ['20/09', 'LA PAROLACCIA', '', '52.600,00', ''],
        ['22/09', 'UBER *TRIP', '', '9.870,00', ''],
    ],
    footer: 'Saldo actual: $ 305.540,00 y U$S 55,49. Pago mínimo: $ 45.000,00.',
    amountColumns: [3, 4],
}

export const SCENARIO_1_TICKETS: readonly UsabilityMaterial[] = [
    {
        kind: 'table',
        title: 'Ticket 1. Verdulería La Huerta',
        notes: ['26/09/2026. Pago: efectivo.'],
        columns: ['Producto', 'Importe'],
        rows: [
            ['Tomate 1 kg', '2.400'],
            ['Papa 2 kg', '2.100'],
            ['Banana 1 kg', '1.950'],
            ['Lechuga', '1.400'],
        ],
        total: ['Total', '7.850'],
        amountColumns: [1],
    },
    {
        kind: 'table',
        title: 'Ticket 2. Farmacity 089',
        notes: ['10/09/2026. Pago: Visa terminada en 4821.'],
        columns: ['Producto', 'Importe'],
        rows: [
            ['Ibuprofeno 600 x20', '9.350'],
            ['Protector solar', '9.400'],
        ],
        total: ['Total', '18.750'],
        amountColumns: [1],
    },
    {
        kind: 'table',
        title: 'Ticket 3. Coto Suc 125',
        notes: ['28/09/2026. Pago: Visa terminada en 4821.'],
        columns: ['Producto', 'Importe'],
        rows: [
            ['Leche x2', '3.600'],
            ['Pan lactal', '2.900'],
            ['Fideos x3', '4.200'],
            ['Aceite 1,5 L', '6.800'],
            ['Detergente', '3.150'],
            ['Carne picada 1 kg', '9.800'],
            ['Queso', '10.780'],
        ],
        total: ['Total', '41.230'],
        amountColumns: [1],
    },
]

const SCENARIO_0_EXPENSES = [
    {
        id: 'g1',
        title: '1 Verdulería',
        detail: 'Hoy, $ 8.500, efectivo. Categoría esperada: Supermercado. Prueba: caso base.',
    },
    {
        id: 'g2',
        title: '2 Taxi',
        detail: 'Hace 3 días, $ 12.000, efectivo. Categoría esperada: Transporte. Prueba: fecha distinta a hoy.',
    },
    {
        id: 'g3',
        title: '3 Café',
        detail: 'Ayer, $ 9.800, MercadoPago. Categoría esperada: Salidas. Prueba: otra cuenta.',
    },
    {
        id: 'g4',
        title: '4 Luz',
        detail: 'Hace 5 días, $ 38.400, MercadoPago. Categoría esperada: Servicios. Prueba: otra cuenta y otra fecha.',
    },
    {
        id: 'g5',
        title: '5 Farmacia',
        detail: 'Hace 2 días, $ 21.300, tarjeta. Categoría esperada: Salud. Prueba: tarjeta.',
    },
    {
        id: 'g6',
        title: '6 Zapatillas',
        detail: 'Hoy, $ 120.000 en 3 cuotas de $ 40.000, tarjeta. Categoría esperada: Ropa. Prueba: cuotas.',
    },
    {
        id: 'g7',
        title: '7 Pago resumen',
        detail: 'Ayer, $ 250.000 desde MercadoPago a la tarjeta. Sin categoría. Prueba: transferencia entre cuentas.',
    },
] as const

const SCENARIO_1_CASES = [
    {
        id: 'cuentas',
        title: 'Cuentas creadas, nombre y moneda',
        detail: 'Qué cuentas crea, con qué nombre y moneda.',
    },
    {
        id: 'dolares',
        title: 'Dólares',
        detail: 'Amazon y Netflix en dólares. Cuenta aparte en USD, conversión a pesos o nada.',
    },
    {
        id: 'cuotas',
        title: 'Cuotas',
        detail: 'Frávega 03/06 y Zara 02/03. Gasto suelto, total de la compra o recurrente.',
    },
    {
        id: 'devolucion',
        title: 'Devolución',
        detail: 'Devolución de MercadoLibre. Como ingreso, borrando el gasto original, o no la carga.',
    },
    {
        id: 'farmacity',
        title: 'Ticket Farmacity, duplicado',
        detail: 'Ya está en el resumen. Si lo carga dos veces.',
    },
    {
        id: 'coto',
        title: 'Ticket Coto, después del cierre',
        detail: 'Pagado con la tarjeta después del cierre. Si lo asigna a la tarjeta.',
    },
    {
        id: 'verduleria',
        title: 'Ticket verdulería, efectivo',
        detail: 'Pagado en efectivo. Si crea una cuenta aparte.',
    },
    {
        id: 'categorias',
        title: 'Categorías y tags',
        detail: 'Si descubre categorías y tags, si crea propios y para qué los usa.',
    },
] as const

export const SCENARIO_2_QUESTIONS = [
    {
        number: 1,
        title: '1 Saldo MercadoPago',
        question: '¿Cuánta plata tenés hoy en MercadoPago?',
        errors: 'Mirar el saldo de otra cuenta o el proyectado con movimientos futuros.',
    },
    {
        number: 2,
        title: '2 Ferretería',
        question:
            'El mes pasado compraste algo en una ferretería. ¿Cuánto pagaste y con qué lo pagaste?',
        errors: '',
    },
    {
        number: 3,
        title: '3 Supermercado',
        question: '¿Cuánto gastaste en supermercado el mes pasado?',
        errors: 'Sumar el mes actual o los últimos 30 días.',
    },
    {
        number: 4,
        title: '4 Comparar meses',
        question:
            '¿Gastaste más el mes pasado o el anterior? ¿Por qué creés que cambió?',
        errors: 'Comparar el mes actual, que está incompleto.',
    },
    {
        number: 5,
        title: '5 Salidas con Martina',
        question:
            '¿Cuánto gastaste en salidas con Martina en los últimos 3 meses?',
        errors: 'Sumar el regalo, la salida de hace 4 meses o todas las salidas.',
    },
    {
        number: 6,
        title: '6 Cuarta cuota',
        question:
            'Compraste una heladera en 6 cuotas. ¿Ya se pagó la cuarta cuota?',
        errors: 'Contar los movimientos futuros como pagados.',
    },
    {
        number: 7,
        title: '7 5.000 USD',
        question:
            'Con lo que ganás y gastás hoy, ¿en cuánto tiempo llegarías a tener 5.000 USD ahorrados?',
        errors: 'Si el asistente usa una cotización real en vez de 1.500, el número cambia. Importa el método y si entiende la respuesta.',
    },
] as const

const OBSERVE_SCENARIO_2 = [
    'Si la resuelve navegando y filtrando a mano o preguntándole al asistente. Es lo más importante de este escenario, sobre todo en las consignas 5, 6 y 7.',
    'La respuesta que da y si coincide con la respuesta esperada.',
    'Si usó el asistente: si entendió lo que le respondió y si lo verificó en la app.',
]

export const SUS_STATEMENTS = [
    'Creo que me gustaría usar esta app con frecuencia.',
    'La app me pareció innecesariamente compleja.',
    'Me pareció que la app era fácil de usar.',
    'Creo que necesitaría ayuda de alguien con conocimientos técnicos para poder usar esta app.',
    'Las distintas funciones de la app me parecieron bien integradas.',
    'Me pareció que la app tenía demasiadas inconsistencias.',
    'Imagino que la mayoría de las personas aprendería a usar esta app muy rápido.',
    'La app me resultó muy engorrosa de usar.',
    'Me sentí con mucha confianza usando la app.',
    'Tuve que aprender muchas cosas antes de poder arrancar con la app.',
] as const

export const SUS_INSTRUCTIONS =
    'Cada afirmación se responde del 1 al 5, donde 1 es "totalmente en desacuerdo" y 5 es "totalmente de acuerdo".'

/** The observation sheet's header rows, label and the options to circle. */
export const OBSERVATION_SHEET_DATA: readonly (readonly [string, string])[] = [
    ['ID de participante', ''],
    ['Grupo', '1 nuevo / 2 usuario'],
    ['Fecha', ''],
    ['Conduce', ''],
    ['Acompaña', ''],
    ['Permiso de grabación', 'Sí / No'],
    ['Versión de la app', ''],
    ['Edad', ''],
    ['Habilidad con la tecnología, 1 a 5', ''],
    ['Cómo registra hoy', ''],
    ['Uso previo de la app', ''],
]

export const OBSERVATION_SHEET_CLOSING: readonly string[] = [
    'Dificultad escenario 0, 1 a 5',
    'Dificultad escenario 1, 1 a 5',
    'Dificultad escenario 2, 1 a 5',
    'Puntaje SUS',
    'Trabas principales',
    'Pistas dadas',
    'Frases textuales',
    'Fallas o pérdida de datos, si pasó',
]

/** Fixed wording of the printed materials, read by participants and the team. */
export const USABILITY_PRINT_TEXT = {
    scenario: (scenario: number) => `Escenario ${scenario}`,
    expenseList: 'Lista de gastos',
    statement: 'Resumen de la tarjeta',
    tickets: 'Tickets',
    cards: 'Tarjetas de consignas. Recortar por la línea punteada.',
    card: (number: number) => `Consigna ${number}`,
    susTitle: 'Cuestionario',
    participant: 'ID de participante',
    date: 'Fecha',
    susStatement: 'Afirmación',
    sheetTitle: 'Planilla de observación',
    sheetHint: 'Una por participante.',
    data: 'Dato',
    value: 'Valor',
    start: 'Inicio',
    end: 'Fin',
    assistantTitle: 'Asistente, completar si lo usó en cualquier escenario',
    question: 'Pregunta',
    answer: 'Respuesta',
    closingTitle: 'Cierre',
} as const

export function susKey(index: number): string {
    return `sus.${index + 1}`
}

const SUS_HINTS = [
    '1 totalmente en desacuerdo',
    '5 totalmente de acuerdo',
] as const

export const USABILITY_STEPS: readonly UsabilityStep[] = [
    {
        id: 'preparacion',
        title: 'Preparación',
        blocks: [
            {
                type: 'fields',
                title: 'Datos de la sesión',
                fields: [
                    { key: 'datos.conduce', kind: 'text', label: 'Conduce' },
                    { key: 'datos.acompana', kind: 'text', label: 'Acompaña' },
                    {
                        key: 'datos.versionApp',
                        kind: 'text',
                        label: 'Versión de la app',
                    },
                ],
            },
            {
                type: 'checklist',
                title: 'Antes de la sesión',
                fields: [
                    {
                        key: 'prep.usuarios',
                        kind: 'check',
                        label: 'Los tres usuarios de la sesión están logueados en el celular, con sesión iniciada y no como cuentas locales.',
                    },
                    {
                        key: 'prep.android',
                        kind: 'check',
                        label: 'Android en español, batería cargada, no molestar activado y sin notificaciones de otras apps.',
                    },
                    {
                        key: 'prep.conexion',
                        kind: 'check',
                        label: 'Conexión estable.',
                    },
                    {
                        key: 'prep.grabador',
                        kind: 'check',
                        label: 'Grabador de audio probado.',
                    },
                    {
                        key: 'prep.materiales',
                        kind: 'check',
                        label: 'Planilla, lápiz y materiales impresos a mano.',
                    },
                ],
            },
            { type: 'credentials', scenario: 0 },
            { type: 'credentials', scenario: 1 },
            { type: 'credentials', scenario: 2 },
            {
                type: 'list',
                title: 'Reglas para quien conduce',
                items: [
                    'Insistí en que lo resuelva sola. Si pregunta cómo se hace algo, devolvé la pregunta: "¿Cómo lo harías vos?", "¿Dónde lo buscarías?".',
                    'Si está trabada y no hay forma de que avance, das una pista. La pista se anota siempre: qué dijiste, en qué escenario y en qué paso. Es de los datos más importantes de la sesión.',
                    'No menciones el asistente ni dónde está, ni nombres botones o pantallas.',
                    'No corrijas errores. Si carga algo mal, se anota y se sigue.',
                    'Si dice "terminé", se acepta aunque falten cosas. Se anota qué faltó.',
                    'Respuestas neutras. Nada de "muy bien" o "perfecto". Alcanza con "gracias, sigamos".',
                    'Si está en una llamada con el asistente, no le hables, porque el asistente también te escucha.',
                ],
            },
            {
                type: 'list',
                title: 'Qué tener en cuenta del modelo de la app',
                items: [
                    'Cada cuenta tiene una sola moneda. Un resumen con pesos y dólares no entra en una sola cuenta.',
                    'No existe un tipo de cuenta "tarjeta de crédito". Una tarjeta es una cuenta más.',
                    'Los movimientos son gasto, ingreso, transferencia o ajuste de saldo. No hay un tipo "devolución".',
                    'Gastos e ingresos pueden ser recurrentes, con frecuencia y fecha de fin opcional. Las cuotas se pueden modelar así. Las transferencias no pueden ser recurrentes.',
                    'En la app el asistente se llama Gaston. En el equipo le decimos Gasti.',
                ],
            },
        ],
    },
    {
        id: 'bienvenida',
        title: 'Bienvenida y consentimiento',
        blocks: [
            { type: 'sessionTimer', action: 'start' },
            {
                type: 'say',
                title: 'Leer o decir con palabras propias',
                paragraphs: [
                    'Gracias por venir. Vamos a probar una app, no a vos. No hay respuestas correctas ni incorrectas: si algo te cuesta, el problema es de la app y es justo lo que queremos encontrar.',
                    'Te vamos a dar un celular y algunas consignas. Mientras las hacés no te podemos ayudar mucho, porque queremos ver cómo lo resolverías si estuvieras solo o sola. Al final contestamos todas tus preguntas.',
                    'Todos los datos que vas a ver son inventados. No hace falta que uses nada tuyo.',
                    '¿Nos das permiso para grabar el audio de la sesión? Lo usamos solo nosotros para no perdernos nada de lo que digas, no lo compartimos. Podés pedir que paremos o cortar la sesión cuando quieras.',
                ],
            },
            {
                type: 'fields',
                fields: [
                    {
                        key: 'consentimiento',
                        kind: 'yesNo',
                        label: 'Permiso de grabación',
                        hint: 'Sin permiso, la sesión sigue solo con notas.',
                    },
                ],
            },
        ],
    },
    {
        id: 'perfil',
        title: 'Preguntas de perfil',
        blocks: [
            {
                type: 'fields',
                fields: [
                    {
                        key: 'perfil.edad',
                        kind: 'text',
                        label: '¿Qué edad tenés?',
                    },
                    {
                        key: 'perfil.habilidad',
                        kind: 'scale',
                        label: 'Del 1 al 5, cuando instalás una app nueva, ¿qué tan fácil te resulta arreglártelas sin ayuda?',
                        hints: [
                            '1 casi siempre necesito que alguien me ayude',
                            '3 me arreglo con las apps que uso seguido',
                            '5 pruebo apps nuevas seguido y las entiendo rápido',
                        ],
                    },
                    {
                        key: 'perfil.registroHoy',
                        kind: 'longText',
                        label: '¿Hoy anotás tus gastos o ingresos de alguna forma? ¿Cómo? ¿Cada cuánto?',
                    },
                    {
                        key: 'perfil.usoPrevio',
                        kind: 'longText',
                        label: '¿Usaste Wallet Bot antes?',
                        hint: 'Solo grupo 2: ¿hace cuánto la usás, cada cuánto la abrís y qué es lo que más usás?',
                    },
                ],
            },
        ],
    },
    {
        id: 'presentacion',
        title: 'Presentación de la app',
        blocks: [
            {
                type: 'note',
                text: 'Decir, sin agregar nada sobre dónde está o cómo se usa el asistente.',
            },
            {
                type: 'say',
                paragraphs: [
                    'Wallet Bot es un anotador de gastos e ingresos pensado para que sea rápido y fácil. También tiene un asistente con inteligencia artificial.',
                ],
            },
        ],
    },
    {
        id: 'escenario-0',
        title: 'Escenario 0: primera impresión',
        blocks: [
            { type: 'credentials', scenario: 0 },
            {
                type: 'material',
                title: 'Lista impresa',
                materials: [SCENARIO_0_EXPENSE_LIST],
            },
            {
                type: 'say',
                title: 'Entregar la lista impresa y leer',
                paragraphs: [
                    'Esta es tu app de gastos y ya tiene tus cuentas cargadas. Esta semana fuiste anotando tus gastos en un papel. Pasalos a la app.',
                ],
            },
            { type: 'scenarioTimer', scenario: 0 },
            {
                type: 'list',
                title: 'Qué observar',
                items: [
                    'Por dónde intenta cargar cada gasto: formulario manual, asistente por texto, nota de voz o modo en vivo. Si cambia de camino en el medio.',
                    'La curva entre gastos: si el segundo y el tercero le llevan menos tiempo y menos dudas que el primero. Marcá la hora de inicio de cada gasto.',
                    'Si usa el asistente, si lo registrado coincide con la lista y si revisa lo que cargó.',
                ],
            },
            {
                type: 'rows',
                title: 'Gastos',
                rowHeader: 'Gasto',
                legend: 'Camino: M formulario manual, T asistente por texto, A nota de voz, V modo en vivo. Dudas: ninguna, pocas o muchas.',
                rows: SCENARIO_0_EXPENSES.map((expense) => ({
                    id: expense.id,
                    title: expense.title,
                    detail: expense.detail,
                    fields: [
                        {
                            key: `e0.${expense.id}.inicio`,
                            kind: 'timestamp',
                            label: 'Hora de inicio',
                        },
                        {
                            key: `e0.${expense.id}.camino`,
                            kind: 'multi',
                            label: 'Camino',
                            options: PATH_OPTIONS,
                        },
                        {
                            key: `e0.${expense.id}.dudas`,
                            kind: 'choice',
                            label: 'Dudas',
                            options: DOUBT_OPTIONS,
                        },
                        {
                            key: `e0.${expense.id}.pista`,
                            kind: 'text',
                            label: 'Pista',
                        },
                        {
                            key: `e0.${expense.id}.quedoBien`,
                            kind: 'yesNo',
                            label: 'Quedó bien',
                        },
                        {
                            key: `e0.${expense.id}.notas`,
                            kind: 'text',
                            label: 'Notas',
                        },
                    ],
                })),
            },
            closingQuestions(0),
            notesBlock('e0'),
        ],
    },
    {
        id: 'escenario-1',
        title: 'Escenario 1: arrancar desde cero',
        blocks: [
            { type: 'credentials', scenario: 1 },
            {
                type: 'material',
                title: 'Resumen impreso',
                materials: [SCENARIO_1_STATEMENT],
            },
            {
                type: 'material',
                title: 'Tickets impresos',
                materials: SCENARIO_1_TICKETS,
            },
            {
                type: 'say',
                title: 'Entregar el resumen y los tickets impresos y leer',
                paragraphs: [
                    'Empezaste a usar Wallet Bot hoy. Te llegó el resumen de la tarjeta y tenés algunos tickets en la billetera. Cargá todo en la app y organizalo como te parezca mejor, como si fuera tu plata.',
                ],
            },
            { type: 'scenarioTimer', scenario: 1 },
            {
                type: 'list',
                title: 'Qué observar',
                items: [
                    'Qué cuentas crea, con qué nombre y moneda, y cómo resuelve los dólares del resumen.',
                    'Cómo carga las cuotas: un gasto suelto por la cuota del mes, el total de la compra o un gasto recurrente.',
                    'Cómo carga la devolución: como ingreso, borrando el gasto original, o no la carga.',
                    'Si separa los tickets de los gastos de la tarjeta. El ticket de Farmacity ya está en el resumen: ¿lo carga dos veces? El de Coto es posterior al cierre: ¿lo asigna a la tarjeta?',
                    'Si descubre categorías y tags, si crea propios y para qué los usa.',
                    'Si usa el asistente, cómo, y si lo que registró coincide con el papel.',
                ],
            },
            {
                type: 'rows',
                title: 'Casos',
                rowHeader: 'Caso',
                legend: 'Camino: M formulario manual, T asistente por texto, A nota de voz, V modo en vivo.',
                rows: SCENARIO_1_CASES.map((item) => ({
                    id: item.id,
                    title: item.title,
                    detail: item.detail,
                    fields: [
                        {
                            key: `e1.${item.id}.queHizo`,
                            kind: 'longText',
                            label: 'Qué hizo',
                        },
                        {
                            key: `e1.${item.id}.camino`,
                            kind: 'multi',
                            label: 'Camino',
                            options: PATH_OPTIONS,
                        },
                        {
                            key: `e1.${item.id}.pista`,
                            kind: 'text',
                            label: 'Pista',
                        },
                        {
                            key: `e1.${item.id}.notas`,
                            kind: 'text',
                            label: 'Notas',
                        },
                    ],
                })),
            },
            closingQuestions(1),
            notesBlock('e1'),
        ],
    },
    {
        id: 'escenario-2',
        title: 'Escenario 2: sacar información',
        blocks: [
            { type: 'credentials', scenario: 2 },
            {
                type: 'say',
                title: 'Leer',
                paragraphs: [
                    'Ahora imaginá que venís usando la app hace 6 meses. Te vamos a hacer algunas preguntas sobre tu plata. Respondelas usando la app.',
                ],
            },
            {
                type: 'note',
                text: 'Entregar las tarjetas de una en una, en este orden.',
            },
            { type: 'scenarioTimer', scenario: 2 },
            {
                type: 'list',
                title: 'Qué observar en cada consigna',
                items: OBSERVE_SCENARIO_2,
            },
            {
                type: 'rows',
                title: 'Consignas',
                rowHeader: '#',
                legend: 'Método: N navegación y filtros, T asistente por texto, A nota de voz, V modo en vivo. Puede ser más de uno.',
                rows: SCENARIO_2_QUESTIONS.map((question) => ({
                    id: `c${question.number}`,
                    title: question.title,
                    detail: question.question,
                    answer: question.number,
                    fields: [
                        {
                            key: `e2.c${question.number}.metodo`,
                            kind: 'multi',
                            label: 'Método',
                            options: METHOD_OPTIONS,
                        },
                        {
                            key: `e2.c${question.number}.respuesta`,
                            kind: 'text',
                            label: 'Respuesta que dio',
                        },
                        {
                            key: `e2.c${question.number}.coincide`,
                            kind: 'yesNo',
                            label: '¿Coincide?',
                        },
                        {
                            key: `e2.c${question.number}.pista`,
                            kind: 'text',
                            label: 'Pista',
                        },
                        {
                            key: `e2.c${question.number}.notas`,
                            kind: 'text',
                            label: 'Notas',
                        },
                    ],
                })),
            },
            closingQuestions(2),
            notesBlock('e2'),
        ],
    },
    {
        id: 'asistente',
        title: 'Uso del asistente',
        blocks: [
            {
                type: 'note',
                text: 'Completar si usó el asistente en cualquier escenario.',
            },
            {
                type: 'fields',
                fields: [
                    {
                        key: 'asistente.escenarios',
                        kind: 'multi',
                        label: '¿En qué escenarios lo usó?',
                        options: [
                            { value: 'e0', label: 'Escenario 0' },
                            { value: 'e1', label: 'Escenario 1' },
                            { value: 'e2', label: 'Escenario 2' },
                        ],
                    },
                    {
                        key: 'asistente.comoEncontro',
                        kind: 'longText',
                        label: '¿Cómo lo encontró?',
                    },
                    {
                        key: 'asistente.canales',
                        kind: 'multi',
                        label: 'Canales que usó',
                        options: [
                            { value: 'texto', label: 'Texto' },
                            { value: 'voz', label: 'Nota de voz' },
                            { value: 'vivo', label: 'Modo en vivo' },
                        ],
                    },
                    {
                        key: 'asistente.entendio',
                        kind: 'longText',
                        label: '¿Registró o respondió lo que la persona quiso decir?',
                    },
                    {
                        key: 'asistente.reviso',
                        kind: 'yesNo',
                        label: '¿Revisó lo que cargó el asistente?',
                    },
                    {
                        key: 'asistente.corrigio',
                        kind: 'longText',
                        label: '¿Corrigió errores del asistente? ¿Cómo?',
                    },
                ],
            },
        ],
    },
    {
        id: 'sus',
        title: 'Cuestionario SUS',
        blocks: [
            {
                type: 'note',
                text: 'Entregar el cuestionario impreso apenas termina el escenario 2, antes de la entrevista, para que responda con la experiencia fresca y sin la influencia de la charla. Después pasar acá sus respuestas.',
            },
            { type: 'sus' },
        ],
    },
    {
        id: 'entrevista',
        title: 'Entrevista',
        blocks: [
            {
                type: 'note',
                text: 'Repreguntar sobre lo concreto que vimos. Si algo ya quedó respondido, se saltea. Evitar preguntas que se contestan con sí o no y empujan la respuesta, como "¿te gustó la app?", "¿te resultó fácil?" o "¿te pareció útil?".',
            },
            {
                type: 'fields',
                fields: [
                    {
                        key: 'entrevista.1',
                        kind: 'longText',
                        label: '1. ¿Cómo te resultó la app?',
                    },
                    {
                        key: 'entrevista.2',
                        kind: 'longText',
                        label: '2. Repasar las trabas anotadas, una por una.',
                        hint: 'Por ejemplo: "Vi que te costó encontrar dónde cargar la cuota, ¿me contás qué estabas pensando?".',
                    },
                    {
                        key: 'entrevista.3',
                        kind: 'longText',
                        label: '3. Si usó el asistente: ¿por qué lo elegiste? ¿Te entendió? ¿Entendiste lo que te respondió? ¿Por qué elegiste escribirle, mandarle un audio o llamarlo? Si no lo usó: ¿lo viste? ¿Por qué no lo usaste?',
                    },
                    {
                        key: 'entrevista.4',
                        kind: 'longText',
                        label: '4. Comparado con cómo registrás tus gastos hoy, o con no registrarlos, ¿cómo te resultó? ¿Te pareció más o menos trabajo?',
                    },
                    {
                        key: 'entrevista.5',
                        kind: 'longText',
                        label: '5. ¿Qué cambiarías?',
                    },
                    {
                        key: 'entrevista.6',
                        kind: 'longText',
                        label: '6. ¿Qué te gustó o te resultó útil?',
                    },
                    {
                        key: 'entrevista.7',
                        kind: 'longText',
                        label: '7. ¿Usarías la app? ¿Por qué sí o por qué no?',
                    },
                    {
                        key: 'entrevista.8',
                        kind: 'longText',
                        label: '8. Solo grupo 2: desde que usás la app, ¿cambió algo en cómo manejás tu plata?',
                    },
                    {
                        key: 'entrevista.9',
                        kind: 'longText',
                        label: '9. ¿Algún otro comentario?',
                    },
                ],
            },
        ],
    },
    {
        id: 'cierre',
        title: 'Cierre',
        blocks: [
            {
                type: 'note',
                text: 'Agradecer, contestar las preguntas que haya guardado y cortar la grabación.',
            },
            { type: 'sessionTimer', action: 'end' },
            { type: 'summary' },
            {
                type: 'fields',
                fields: [
                    {
                        key: 'cierre.trabas',
                        kind: 'longText',
                        label: 'Trabas principales',
                    },
                    {
                        key: 'cierre.pistas',
                        kind: 'longText',
                        label: 'Pistas dadas',
                    },
                    {
                        key: 'cierre.frases',
                        kind: 'longText',
                        label: 'Frases textuales',
                    },
                    {
                        key: 'cierre.fallas',
                        kind: 'longText',
                        label: 'Fallas o pérdida de datos, si pasó',
                    },
                ],
            },
            { type: 'recording' },
        ],
    },
]

function collectFields(): Map<string, UsabilityField> {
    const map = new Map<string, UsabilityField>()
    const add = (field: UsabilityField) => {
        if (map.has(field.key)) {
            throw new Error(`Duplicate usability field ${field.key}`)
        }
        map.set(field.key, field)
    }
    add({ key: SESSION_START_KEY, kind: 'timestamp', label: 'Inicio' })
    add({ key: SESSION_END_KEY, kind: 'timestamp', label: 'Fin' })
    for (const scenario of USABILITY_SCENARIOS) {
        add({
            key: scenarioStartKey(scenario),
            kind: 'timestamp',
            label: 'Inicio',
        })
        add({ key: scenarioEndKey(scenario), kind: 'timestamp', label: 'Fin' })
    }
    SUS_STATEMENTS.forEach((statement, index) => {
        add({
            key: susKey(index),
            kind: 'scale',
            label: `${index + 1}. ${statement}`,
            hints: SUS_HINTS,
        })
    })
    for (const step of USABILITY_STEPS) {
        for (const block of step.blocks) {
            if (block.type === 'fields' || block.type === 'checklist') {
                block.fields.forEach(add)
            } else if (block.type === 'rows') {
                for (const row of block.rows) row.fields.forEach(add)
            }
        }
    }
    return map
}

export const USABILITY_FIELDS: ReadonlyMap<string, UsabilityField> =
    collectFields()

export type UsabilityFieldValue = string | number | boolean | string[] | null

/**
 * Checks a value against its field's kind. Returns an error message, or null
 * when the value is acceptable. `null` always clears a field.
 */
export function usabilityFieldError(
    key: string,
    value: UsabilityFieldValue,
): string | null {
    const field = USABILITY_FIELDS.get(key)
    if (!field) return `Unknown field ${key}`
    if (value === null) return null
    switch (field.kind) {
        case 'text':
            return typeof value === 'string' &&
                value.length <= USABILITY_TEXT_MAX_LENGTH
                ? null
                : `${key} must be a short string`
        case 'longText':
            return typeof value === 'string' &&
                value.length <= USABILITY_LONG_TEXT_MAX_LENGTH
                ? null
                : `${key} must be a string`
        case 'scale':
            return typeof value === 'number' &&
                Number.isInteger(value) &&
                value >= 1 &&
                value <= 5
                ? null
                : `${key} must be an integer from 1 to 5`
        case 'yesNo':
        case 'check':
            return typeof value === 'boolean'
                ? null
                : `${key} must be a boolean`
        case 'timestamp':
            return typeof value === 'number' &&
                Number.isFinite(value) &&
                value > 0
                ? null
                : `${key} must be a timestamp`
        case 'choice':
            return typeof value === 'string' &&
                field.options.some((option) => option.value === value)
                ? null
                : `${key} must be one of its options`
        case 'multi': {
            if (!Array.isArray(value)) return `${key} must be a list`
            const allowed = new Set(field.options.map((option) => option.value))
            const unique = new Set(value)
            return unique.size === value.length &&
                value.every((item) => allowed.has(item))
                ? null
                : `${key} must list distinct options`
        }
    }
}

/**
 * The System Usability Scale score, 0 to 100, or null until all ten
 * statements are answered. Odd statements count `answer - 1`, even ones
 * `5 - answer`, and the sum is multiplied by 2.5.
 */
export function susScore(
    answers: readonly (number | undefined)[],
): number | null {
    if (answers.length !== SUS_STATEMENTS.length) return null
    let sum = 0
    for (let index = 0; index < answers.length; index += 1) {
        const answer = answers[index]
        if (answer === undefined) return null
        sum += index % 2 === 0 ? answer - 1 : 5 - answer
    }
    return sum * 2.5
}

/** Amounts are in cents; days are `YYYY-MM-DD`. */
export type Scenario2Answers = {
    mercadoPagoBalanceCents: number
    hardware: { amountCents: number; accountName: string; day: string }
    supermarket: { totalCents: number; count: number }
    months: {
        previousMonth: string
        lastMonth: string
        previousTotalCents: number
        lastTotalCents: number
        categories: {
            name: string
            previousCents: number
            lastCents: number
        }[]
    }
    martina: {
        totalCents: number
        count: number
        withGiftCents: number
        withOldOutingCents: number
    }
    fridge: { paidCount: number; fourthDueDay: string }
    savings: {
        currentUsdCents: number
        goalUsdCents: number
        monthlyUsdCents: number
        months: number
    }
}

const ARS = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 0 })
const USD = new Intl.NumberFormat('es-AR', { maximumFractionDigits: 2 })

export function formatArsCents(cents: number): string {
    const sign = cents < 0 ? '-' : ''
    return `${sign}$ ${ARS.format(Math.abs(cents) / 100)}`
}

export function formatUsdCents(cents: number): string {
    return `USD ${USD.format(cents / 100)}`
}

function formatDay(day: string): string {
    const [year, month, date] = day.split('-')
    return `${date}/${month}/${year}`
}

export function scenario2ExpectedAnswer(
    question: number,
    answers: Scenario2Answers,
): string {
    switch (question) {
        case 1:
            return formatArsCents(answers.mercadoPagoBalanceCents)
        case 2:
            return `${formatArsCents(answers.hardware.amountCents)}, en ${answers.hardware.accountName.toLowerCase()}, el ${formatDay(answers.hardware.day)}.`
        case 3:
            return `${formatArsCents(answers.supermarket.totalCents)} en ${answers.supermarket.count} compras.`
        case 4: {
            const { months } = answers
            const delta = months.lastTotalCents - months.previousTotalCents
            const top = [...months.categories].sort(
                (a, b) =>
                    Math.abs(b.lastCents - b.previousCents) -
                    Math.abs(a.lastCents - a.previousCents),
            )
            const breakdown = top
                .filter((item) => item.lastCents !== item.previousCents)
                .slice(0, 4)
                .map(
                    (item) =>
                        `${item.name} ${formatArsCents(item.lastCents - item.previousCents)}`,
                )
                .join(', ')
            const which = delta >= 0 ? 'Más el mes pasado' : 'Más el anterior'
            return `${which}: ${formatArsCents(months.lastTotalCents)} contra ${formatArsCents(months.previousTotalCents)}, una diferencia de ${formatArsCents(Math.abs(delta))}. Por categoría: ${breakdown}.`
        }
        case 5:
            return `${formatArsCents(answers.martina.totalCents)} en ${answers.martina.count} salidas. ${formatArsCents(answers.martina.withGiftCents)} si suma el regalo, ${formatArsCents(answers.martina.withOldOutingCents)} si suma la salida de hace 4 meses.`
        case 6:
            return `No. Se pagaron ${answers.fridge.paidCount}, la cuarta vence el ${formatDay(answers.fridge.fourthDueDay)}.`
        case 7: {
            const missing =
                answers.savings.goalUsdCents - answers.savings.currentUsdCents
            return `Unos ${answers.savings.months} meses: tiene ${formatUsdCents(answers.savings.currentUsdCents)}, faltan ${formatUsdCents(missing)} y ahorra unos ${formatUsdCents(answers.savings.monthlyUsdCents)} por mes. Aceptar entre ${answers.savings.months - 2} y ${answers.savings.months + 2}.`
        }
        default:
            return ''
    }
}
