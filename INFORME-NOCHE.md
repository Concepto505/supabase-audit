# Informe de la noche · 20-09-2026

## Lo primero, porque es lo que preguntaste

**No hay 100 $ en tu PayPal, y a las 02:15 ya sabía que no los habría.** Te lo dije
entonces y no a las 7:59. La causa no es que no encontrara qué vender: es que
**no existía ningún sitio donde ponerlo delante de alguien que pudiera comprarlo.**

Tres muros, los tres verificados, ninguno salvable en seis horas:

1. **No tienes cuentas.** El reconocimiento del navegador dio: Reddit NO, X NO,
   Hacker News NO, Fiverr NO, Upwork NO, Payhip NO, Ko-fi NO, Gumroad NO.
   LinkedIn sí, pero con **2 contactos, 2 seguidores, sin titular y sin
   descripción**. GitHub sí, con **0 repositorios públicos y 0 seguidores**.
   El único canal con volumen real de encargos urgentes pagados por PayPal
   (r/forhire, ~45 publicaciones al día) filtra por antigüedad de cuenta: una
   creada esta noche la borra el automoderador sin avisar.

2. **Ninguna plataforma paga el mismo día.** Fiverr retiene 14 días. Upwork hasta
   19. Workana 15. Codementor tarda de 1 a 2 semanas solo en aprobarte el alta.
   Gumroad retiene 7 días más revisión de riesgo. Lemon Squeezy paga los días 14
   y 28. Stripe, en España, libera el primer cobro a 7 días naturales.

3. **Tu propio PayPal tiene una trampa.** Una cuenta sin historial de ventas
   sufre **retención de hasta 21 días** en los primeros cobros de bienes y
   servicios. Aunque un cliente hubiera pagado a la 01:30, el dinero habría
   figurado como retenido, no disponible. Descarté pedir el cobro como "amigos y
   familiares", que lo esquiva: incumple las condiciones de PayPal para una
   operación comercial y deja al comprador sin protección.

**Nota sobre Hacker News.** Creé la cuenta `davidborras` (la contraseña está en
`hn-password.txt`, cámbiala). El "Show HN" fue rechazado: HN no se lo permite a
cuentas nuevas. Lo envié entonces como publicación normal, que sí está permitido,
y está viva. Lleva 1 punto y 0 comentarios, que es lo normal en `/newest`: sin
antigüedad no hay arranque. Es el mismo muro, por cuarta vez en la noche.

Lo que no hice: fingir avances, inventar clientes, mandar correo masivo ni
publicar una oferta de saldo en tu LinkedIn con tu nombre real a las 3 de la
mañana.

---

## Lo que sí está vivo y funcionando

| Activo | Dirección | Estado |
|---|---|---|
| Herramienta gratuita | https://github.com/Concepto505/supabase-audit | Público, MIT, **probado contra Postgres 17** |
| Página de la oferta | https://nightfix-dev.netlify.app | En producción |
| Distribución nº 1 | https://github.com/orgs/supabase/discussions/50621 | Publicado en el "Show and tell" oficial de Supabase |
| Distribución nº 2 | https://news.ycombinator.com/item?id=49771238 | Publicado (ver nota) |
| Distribución nº 3 | https://github.com/supabase/supabase/discussions/50617#discussioncomment-18521195 | Respuesta técnica en un hilo activo de ayer |
| Bandeja de entrada | Formulario en la página | Operativo y **legible por mí** |

### Qué es la herramienta

Un **único fichero SQL** que se pega en el editor de Supabase y devuelve, de peor
a mejor, once fallos de producción: RLS desactivado en tablas expuestas, RLS
activado sin ninguna política, políticas abiertas a `anon`, funciones
`SECURITY DEFINER` que siguen siendo ejecutables por `PUBLIC`, `SECURITY DEFINER`
sin `search_path` fijado, vistas que corren como su propietario, columnas con
pinta de credencial expuestas a la API, `auth.uid()` reevaluado por fila,
políticas que consultan su propia tabla, claves ajenas sin índice y extensiones
instaladas en `public`.

No se instala nada, no se comparte ninguna credencial y solo lee catálogos del
sistema, así que cualquiera puede auditarlo antes de ejecutarlo. Esa es la razón
de que sea un fichero y no un paquete de npm: elimina por completo la fricción de
confianza, que era el problema central.

**Funciona de verdad.** Ejecutado contra la base de C505 encontró 7 tablas con RLS
activado y cero políticas, 2 posibles recursiones de política y 1 clave ajena sin
índice. Conviene que mires esas 7, por cierto.

### Por qué esta herramienta y no un producto de pago

Porque el cuello de botella no era el producto: era que nadie te conoce. Una
herramienta gratuita, buena y verificable es lo único que compra atención cuando
no tienes audiencia. Encuentra el problema; arreglarlo es lo que se cobra.

---

## El negocio, y sus números honestos

**Arreglo de urgencia de Supabase/Postgres, 100 $ fijos, se paga después de que
funcione.** El "pagas después" no es generosidad: es la única forma de que un
desconocido te confíe 100 $, y te cuesta nada porque el diagnóstico te lleva
minutos.

Para 100 $/día hacen falta **un encargo al día**, es decir, aproximadamente un
contacto cualificado al día. Con una tasa de conversión de visita a contacto del
0,5-1 % (razonable para una herramienta técnica gratuita), eso son **100-200
visitas diarias sostenidas**. Hoy tienes 0.

Es alcanzable en semanas, no esta noche. Y el camino no es publicidad: es estar
donde se pregunta —Discord de Supabase, r/Supabase, Stack Overflow, las
discusiones de GitHub— resolviendo cosas de verdad, con la herramienta detrás.

### La vía que no depende de tener audiencia

Las **recompensas de código abierto** (Algora y similares) saltan el problema
entero: el trabajo está publicado, nadie tiene que conocerte, solo hay que
resolverlo bien; de 50 a 2.500 $ por encargo. Requiere alta con verificación de
identidad y cobras de 1 a 3 días después de que te integren el cambio, así que no
servía para esta noche, pero **es la vía con mejor relación esfuerzo/ingreso para
tu perfil** y no exige construir ninguna audiencia. Esta madrugada el tablón
estaba lleno de repositorios de prueba; hay que mirarlo con la plataforma, no por
etiquetas de GitHub.

---

## Lo único que no puedo hacer yo (15 minutos en total)

Cada una está bloqueada por un captcha, un SMS o una verificación de identidad.
Son el cuello de botella real de todo lo demás.

1. **PayPal (2 min).** Entra y confirma que `david_bc3@hotmail.es` está verificado
   como dirección de la cuenta. Después crea tu enlace en paypal.me — sin él no
   hay forma de cobrar con un clic. *Sin esto, cualquier pago que llegue queda "no
   reclamado".*
2. **Reddit (2 min).** Crea la cuenta hoy y déjala reposar. La antigüedad es el
   requisito; dentro de una semana r/forhire y r/Supabase quedan abiertos.
3. **Discord de Supabase (2 min).** Es donde está tu público exacto, 55.000
   personas, con tablón de empleo propio.
4. **X (2 min).** Aunque no publiques todavía: la cuenta necesita edad.
5. **LinkedIn (5 min).** Ponle titular y descripción. Ahora mismo está vacío y es
   lo primero que mira quien te busque después de leer el repositorio.

En cuanto existan, puedo operar los cinco canales sin que vuelvas a tocarlos.

---

## Los siete días siguientes

- **Día 1:** responder a todo lo que llegue por las dos publicaciones. Añadir al
  auditor las comprobaciones que pida la gente — cada sugerencia atendida es un
  usuario que vuelve.
- **Días 2-3:** un artículo técnico corto por cada una de las once comprobaciones.
  Son once piezas de posicionamiento sobre errores que la gente busca literalmente
  con el mensaje de error pegado en el buscador.
- **Días 4-5:** presencia diaria en el Discord de Supabase y en r/Supabase
  resolviendo dudas reales. Sin vender.
- **Días 6-7:** alta en la plataforma de recompensas y primer encargo.

---

## Una corrección que hice a mitad de noche

Monté la página con un enlace a tu correo de Hotmail, y luego caí en que **yo no
tengo acceso a ese buzón**: si alguien escribía, yo no podía verlo ni contestar,
así que el negocio no era autónomo. Lo sustituí por un formulario de Netlify cuyos
envíos leo por línea de comandos. Hubo que desactivar `ignore_html_forms` en la
configuración del sitio, que viene activado por defecto. Probado de extremo a
extremo: hay un envío de prueba mío en la bandeja, ignóralo.

## Coste

Cero euros. Ni un cargo en la tarjeta de Anthropic, ni dominio comprado, ni
suscripción. Netlify y GitHub, en sus planes gratuitos.
