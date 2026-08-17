# Omatchday

Omatchday es un centro de partidos para Omarchy: equipos favoritos, próximos encuentros, resultados anteriores, estados en vivo y calendario mensual, usando los colores del tema activo.

![Omatchday preview](preview.svg)

## Estado

Primera versión funcional. La interfaz vive como servicio de Quickshell y obtiene datos de fútbol directamente desde ESPN, sin API key ni proxy propio. La fuente puede cambiarse en el backend más adelante sin rehacer la UI.

## Instalar localmente

Desde este repositorio:

```bash
bash configure-omatchday.sh
```

El configurador pregunta por códigos de ligas ESPN y permite escoger equipos por número. Algunos ejemplos:

- `eng.1` — Premier League
- `esp.1` — LaLiga
- `ita.1` — Serie A
- `ger.1` — Bundesliga
- `fra.1` — Ligue 1
- `mex.1` — Liga MX
- `conmebol.libertadores` — Copa Libertadores

La configuración queda en `~/.config/omarchy/omatchday/config.json` con permisos `600`.

Para instalar el candidato como plugin local:

```bash
omarchy plugin add /home/brm/omatchday --yes
omarchy plugin enable io.github.brm-src.omatchday
omarchy-shell shell rescanPlugins
```

El plugin se puede abrir/cerrar desde IPC:

```bash
omarchy-shell shell toggle io.github.brm-src.omatchday
```

## Qué muestra

- Próximo partido destacado.
- Hasta cinco partidos próximos.
- Hasta cinco resultados anteriores.
- Estado en vivo y marcador.
- Competición, estadio y ciudad cuando la API los entrega.
- Vista mensual con días que tienen partidos.
- Logos remotos con fallback a abreviaturas.
- Refresh manual y automático.
- Oculta la tarjeta cuando hay una ventana activa para no invadir aplicaciones.

## Configuración avanzada

```json
{
  "leagues": ["eng.1", "esp.1"],
  "teams": [
    {
      "id": "359",
      "name": "Arsenal",
      "shortName": "Arsenal",
      "abbreviation": "ARS",
      "logo": "https://a.espncdn.com/i/teamlogos/soccer/500/359.png",
      "color": "e20520",
      "alternateColor": "003399"
    }
  ],
  "daysBack": 45,
  "daysForward": 90,
  "refreshMinutes": 15
}
```

Omatchday solo envía consultas HTTPS a la API pública de ESPN. No solicita credenciales ni instala paquetes. La API puede tener límites, cambios de cobertura o retrasos; esos estados se muestran en la interfaz en lugar de inventar resultados.

## Validación

```bash
python3 -m unittest discover -s tests -v
python3 -m py_compile omatchday.py
qmllint -I /usr/share/omarchy/shell Omatchday.qml
omarchy plugin validate .
bash -n configure-omatchday.sh
git diff --check
```

## Licencia

MIT.
