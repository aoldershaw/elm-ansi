module Ansi.Log (Model, LineDiscipline(..), Line, Chunk, CursorPosition, Style, init, update, view) where

{-| Log interprets a stream of text and ANSI escape codes.

@docs init, update, view

@docs Model, LineDiscipline, Line, Chunk, CursorPosition, Style
-}

import Array exposing (Array)
import Html
import Html.Attributes
import Html.Lazy
import String

import Ansi

{-| Model is populated by parsing ANSI character sequences and escape codes
via `update`.

* `lines` contains all of the output that's been parsed
* `position` is the current position of the cursor
* `style` is the style to be applied to any text that's printed
* `remainder` is a partial ANSI escape sequence left around from an incomplete
  segment from the stream
-}
type alias Model =
  { lineDiscipline : LineDiscipline
  , lines : Array Line
  , position : CursorPosition
  , savedPosition : Maybe CursorPosition
  , style : Style
  , remainder : String
  }

{-| A list of arbitrarily-sized chunks of output.
-}
type alias Line = Array Chunk

{-| A blob of text paired with the style that was configured at the time.
-}
type alias Chunk =
  { text : String
  , style : Style
  }

{-| The current presentation state for any text that's printed.
-}
type alias Style =
  { foreground : Maybe Ansi.Color
  , background : Maybe Ansi.Color
  , bold : Bool
  , faint : Bool
  , italic : Bool
  , underline : Bool
  , inverted : Bool
  }

{-| The coordinate in the window where text will be printed.
-}
type alias CursorPosition =
  { row : Int
  , column : Int
  }

{-| How to interpret linebreaks.

* `Raw`: interpret `\n` as just `\n`, i.e. move down a line, retaining the
  cursor column
* `Cooked`: interpret `\n` as `\r\n`, i.e. move down a line and go to the first
  column
-}
type LineDiscipline
  = Raw
  | Cooked

{-| Construct an empty model.
-}
init : LineDiscipline -> Model
init ldisc =
  { lineDiscipline = ldisc
  , lines = Array.empty
  , position = { row = 0, column = 0 }
  , savedPosition = Nothing
  , style =
    { foreground = Nothing
    , background = Nothing
    , bold = False
    , faint = False
    , italic = False
    , underline = False
    , inverted = False
    }
  , remainder = ""
  }

{-| Parse and interpret a chunk of ANSI output.

Trailing partial ANSI escape codes will be prepended to the chunk in the next
call to `update`.
-}
update : String -> Model -> Model
update str model =
  Ansi.parseInto
    { model | remainder = "" }
    handleAction
    (model.remainder ++ str)

blankLine : Line
blankLine =
  Array.empty

handleAction : Ansi.Action -> Model -> Model
handleAction action model =
  case action of
    Ansi.Print s ->
      let
        chunk = Chunk s model.style
        update = writeChunk model.position.column chunk
      in
        { model | lines = updateLine model.position.row update model.lines
                , position = moveCursor 0 (String.length s) model.position }

    Ansi.CarriageReturn ->
      { model | position = CursorPosition model.position.row 0 }

    Ansi.Linebreak ->
      handleAction (Ansi.Print "") <|
        case model.lineDiscipline of
          Raw ->
            { model | position = moveCursor 1 0 model.position }

          Cooked ->
            { model | position = CursorPosition (model.position.row + 1) 0 }

    Ansi.Remainder s ->
      { model | remainder = s }

    Ansi.CursorUp num ->
      { model | position = moveCursor (-num) 0 model.position }

    Ansi.CursorDown num ->
      { model | position = moveCursor num 0 model.position }

    Ansi.CursorForward num ->
      { model | position = moveCursor 0 num model.position }

    Ansi.CursorBack num ->
      { model | position = moveCursor 0 (-num) model.position }

    Ansi.CursorPosition row col ->
      { model | position = CursorPosition (row - 1) (col - 1) }

    Ansi.CursorColumn col ->
      { model | position = CursorPosition model.position.row col }

    Ansi.SaveCursorPosition ->
      { model | savedPosition = Just model.position }

    Ansi.RestoreCursorPosition ->
      { model | position = Maybe.withDefault model.position model.savedPosition }

    Ansi.EraseLine mode ->
      case mode of
        Ansi.EraseToBeginning ->
          let
            chunk = Chunk (String.repeat model.position.column " ") model.style
            update = writeChunk 0 chunk
          in
            { model | lines = updateLine model.position.row update model.lines }

        Ansi.EraseToEnd ->
          let
            update = takeLen blankLine model.position.column
          in
            { model | lines = updateLine model.position.row update model.lines }

        Ansi.EraseAll ->
          { model | lines = updateLine model.position.row (always blankLine) model.lines }

    _ ->
      { model | style = updateStyle action model.style }

moveCursor : Int -> Int -> CursorPosition -> CursorPosition
moveCursor r c pos =
  { pos | row = pos.row + r, column = pos.column + c }

updateLine : Int -> (Line -> Line) -> Array Line -> Array Line
updateLine row update lines =
  let
    currentLines = Array.length lines
    line = update <| Maybe.withDefault blankLine (Array.get row lines)
  in
    if row + 1 > currentLines
      then appendLine (row - currentLines) line lines
      else Array.set row line lines

appendLine : Int -> Line -> Array Line -> Array Line
appendLine after line lines =
  if after == 0
     then Array.push line lines
     else appendLine (after - 1) line (Array.push blankLine lines)

updateStyle : Ansi.Action -> Style -> Style
updateStyle action style =
  case action of
    Ansi.SetForeground mc ->
      { style | foreground = mc }

    Ansi.SetBackground mc ->
      { style | background = mc }

    Ansi.SetInverted b ->
      { style | inverted = b }

    Ansi.SetBold b ->
      { style | bold = b }

    Ansi.SetFaint b ->
      { style | faint = b }

    Ansi.SetItalic b ->
      { style | italic = b }

    Ansi.SetUnderline b ->
      { style | underline = b }

    _ ->
      style

writeChunk : Int -> Chunk -> Line -> Line
writeChunk pos chunk line =
  if pos == lineLen line then
    Array.push chunk line
  else
    insertChunkAt pos chunk line

insertChunkAt : Int -> Chunk -> Line -> Line
insertChunkAt pos chunk line =
  let
    chunksBefore = takeLen blankLine pos line
    chunksLen = lineLen chunksBefore

    before =
      if chunksLen < pos
         then Array.push { style = chunk.style, text = String.repeat (pos - chunksLen) " " } chunksBefore
         else chunksBefore

    after = dropLen (pos + String.length chunk.text) line
  in
    Array.append (Array.push chunk before) after

type alias DropState = (Int, Line)

type alias TakeState = (Int, Line)

dropLen : Int -> Line -> Line
dropLen len line =
  snd (Array.foldl dropChunk (len, blankLine) line)

dropChunk : Chunk -> DropState -> DropState
dropChunk chunk (toDrop, droppedLine) =
  if toDrop == 0 then
    (0, Array.push chunk droppedLine)
  else
    let
      chunkLen = String.length chunk.text
    in
      if chunkLen > toDrop then
        (0, Array.push { chunk | text = String.dropLeft toDrop chunk.text } droppedLine)
      else
        (toDrop - chunkLen, droppedLine)

takeLen : Array Chunk -> Int -> Line -> Line
takeLen acc len line =
  snd (Array.foldl takeChunk (len, blankLine) line)

takeChunk : Chunk -> TakeState -> TakeState
takeChunk chunk (toTake, takenLine) =
  if toTake == 0 then
    (0, takenLine)
  else
    let
      chunkLen = String.length chunk.text
    in
      if chunkLen < toTake then
        (toTake - chunkLen, Array.push chunk takenLine)
      else
        (0, Array.push { chunk | text = String.left toTake chunk.text } takenLine)

lineLen : Line -> Int
lineLen line =
  Array.foldl (\chunk acc -> String.length chunk.text + acc) 0 line

{-| Render the model's logs as HTML.

Wraps everything in <pre>, with a <div> for each Line, and <span> with styling
and classes for each Chunk.

The `span` elements will have the following attributes:

* `style="font-weight: bold|normal"`
* `class="ansi-COLOR-fg ansi-COLOR-bg ansi-bold"`

...where each class is optional, and `COLOR` is one of:

* `black`
* `red`
* `green`
* `yellow`
* `blue`
* `magenta`
* `cyan`
* `white`
* `bright-black`
* `bright-red`
* `bright-green`
* `bright-yellow`
* `bright-blue`
* `bright-magenta`
* `bright-cyan`
* `bright-white`

If the chunk is inverted, the `-fg` and `-bg` classes will have their colors
swapped. If the chunk is bold, the `ansi-bold` class will be present.
-}
view : Model -> Html.Html
view model =
  Html.pre []
    (Array.toList (Array.map lazyLine model.lines))

lazyLine : Line -> Html.Html
lazyLine = Html.Lazy.lazy viewLine

viewLine : Line -> Html.Html
viewLine line =
  Html.div [] (Array.toList <| Array.push (Html.text "\n") <| Array.map viewChunk line)

viewChunk : Chunk -> Html.Html
viewChunk chunk =
  Html.span (styleAttributes chunk.style)
    [Html.text chunk.text]

styleAttributes : Style -> List Html.Attribute
styleAttributes style =
  [ Html.Attributes.style [("font-weight", if style.bold then "bold" else "normal")]
  , let
      fgClasses =
        colorClasses "-fg"
          style.bold
          (if not style.inverted then style.foreground else style.background)
      bgClasses =
        colorClasses "-bg"
          style.bold
          (if not style.inverted then style.background else style.foreground)
    in
      Html.Attributes.classList (List.map (flip (,) True) (fgClasses ++ bgClasses))
  ]

colorClasses : String -> Bool -> Maybe Ansi.Color -> List String
colorClasses suffix bold mc =
  let
    brightPrefix = "ansi-bright-"

    prefix =
      if bold then
        brightPrefix
      else
        "ansi-"
  in
    case mc of
      Nothing ->
        if bold then
          ["ansi-bold"]
        else
          []
      Just (Ansi.Black) ->   [prefix ++ "black" ++ suffix]
      Just (Ansi.Red) ->     [prefix ++ "red" ++ suffix]
      Just (Ansi.Green) ->   [prefix ++ "green" ++ suffix]
      Just (Ansi.Yellow) ->  [prefix ++ "yellow" ++ suffix]
      Just (Ansi.Blue) ->    [prefix ++ "blue" ++ suffix]
      Just (Ansi.Magenta) -> [prefix ++ "magenta" ++ suffix]
      Just (Ansi.Cyan) ->    [prefix ++ "cyan" ++ suffix]
      Just (Ansi.White) ->   [prefix ++ "white" ++ suffix]
      Just (Ansi.BrightBlack) ->   [brightPrefix ++ "black" ++ suffix]
      Just (Ansi.BrightRed) ->     [brightPrefix ++ "red" ++ suffix]
      Just (Ansi.BrightGreen) ->   [brightPrefix ++ "green" ++ suffix]
      Just (Ansi.BrightYellow) ->  [brightPrefix ++ "yellow" ++ suffix]
      Just (Ansi.BrightBlue) ->    [brightPrefix ++ "blue" ++ suffix]
      Just (Ansi.BrightMagenta) -> [brightPrefix ++ "magenta" ++ suffix]
      Just (Ansi.BrightCyan) ->    [brightPrefix ++ "cyan" ++ suffix]
      Just (Ansi.BrightWhite) ->   [brightPrefix ++ "white" ++ suffix]
