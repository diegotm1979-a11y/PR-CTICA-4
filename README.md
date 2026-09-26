# Base de Datos de Jugadores — Web App

Web app local con filtros para explorar la base de datos de scouting
(`Archivo Individualidades.numbers`), que se actualiza sola cuando añades
o editas jugadores en el archivo de Numbers.

## Uso

```bash
./start.sh
```

Esto:
1. Vigila el archivo `.numbers` en segundo plano. Cuando lo guardas (o si
   ya lo tienes abierto y Numbers autoguarda), espera unos segundos a que
   se asienten los cambios, lo exporta a Excel y regenera los datos.
2. Abre la web app en `http://localhost:8743`.

La web app comprueba cada 8 segundos si hay datos nuevos y se refresca
sola, sin perder los filtros aplicados.

Para detenerlo, vuelve a la terminal donde lo lanzaste y pulsa `Ctrl+C`.

## Notas

- La primera sincronización tarda 2-3 minutos porque el archivo es grande
  (~50 MB) y Numbers necesita abrirlo y exportarlo por completo. Las
  siguientes veces es igual de lento porque siempre exporta el archivo
  entero (no hay forma más rápida de leer un `.numbers` sin Numbers).
- Si tienes el archivo abierto en Numbers mientras editas, el script
  reutiliza esa misma ventana en vez de abrir una copia — no interrumpe tu
  edición ni cierra el documento que ya tenías abierto.
- `scripts/extract.py` es quien interpreta la estructura del archivo
  (tabla maestra `BASE DE DATOS` + fichas individuales por jugador). Si
  cambias el diseño de las hojas o de la plantilla, este script es el que
  habría que ajustar.
