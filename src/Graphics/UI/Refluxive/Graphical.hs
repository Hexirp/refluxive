{-# LANGUAGE TypeOperators, OverloadedLabels, FlexibleContexts, PolyKinds #-}
module Graphics.UI.Refluxive.Graphical
  ( Graphical
  , RenderState(..)
  , defRenderState

  , empty
  , text
  , gridLayout
  , rectangle
  , rectangleWith
  , colored
  , translate
  , graphics
  , clip
  , viewInfo

  , render
  ) where

import qualified SDL as SDL
import qualified SDL.Primitive as SDL
import qualified SDL.Font as SDLF
import Linear.V2
import Control.Lens ((^.), (.~), (&))
import Control.Monad.Trans
import Data.Extensible
import qualified Data.Text as T
import Data.Maybe
import Foreign.C.Types
import System.Mem

type ShapeStyle =
  [ "fill" >: Bool
  , "rounded" >: Maybe Int
  ]

defShapeStyle :: Record ShapeStyle
defShapeStyle
  = #fill @= True
  <: #rounded @= Nothing
  <: nil

data Graphical
  = Empty
  | GridLayout SDL.Pos Graphical
  | Rectangle (Record ShapeStyle) SDL.Pos SDL.Pos
  | Colored SDL.Color Graphical
  | Translate SDL.Pos Graphical
  | Graphics [Graphical]
  | Text T.Text
  | Clip SDL.Pos Graphical
  | ViewInfo String Graphical

data RenderState
  = RenderState
  { color :: SDL.Color
  , coordinate :: SDL.Pos
  , scaler :: SDL.Pos
  }

defRenderState :: RenderState
defRenderState
  = RenderState
  { color = SDL.V4 0 0 0 255
  , coordinate = SDL.V2 0 0
  , scaler = SDL.V2 1 1
  }

render :: MonadIO m => SDLF.Color -> Maybe SDLF.Font -> SDL.Renderer -> Graphical -> (RenderState -> String -> m ()) -> m ()
render clearColor mfont renderer g cont = go defRenderState g >> liftIO performGC where
  go st Empty = return ()
  go st (GridLayout s g) = go (st { scaler = s }) g
  go st (Rectangle style pos size) = do
    let topLeft = pos * scaler st + coordinate st
    let bottomRight = (pos + size) * scaler st + coordinate st
    case (style ^. #fill, fmap toEnum $ style ^. #rounded) of
      (True, Just r) -> SDL.fillRoundRectangle renderer topLeft bottomRight r (color st)
      (True, Nothing) -> SDL.fillRectangle renderer topLeft bottomRight (color st)
      (False, Just r) -> SDL.roundRectangle renderer topLeft bottomRight r (color st)
      (False, Nothing) -> SDL.rectangle renderer topLeft bottomRight (color st)
  go st (Colored color g) = go (st { color = color }) g
  go st (Translate p g) = go (st { coordinate = coordinate st + p * scaler st }) g
  go st (Graphics gs) = mapM_ (go st) gs
  go st (Text txt) | T.null txt = return ()
  go st (Text txt) = do
    surface <- SDLF.blended (fromJust mfont) (color st) txt
    texture <- SDL.createTextureFromSurface renderer surface
    SDL.textureBlendMode texture SDL.$= SDL.BlendAlphaBlend
    tinfo <- SDL.queryTexture texture
    let size = V2 (SDL.textureWidth tinfo) (SDL.textureHeight tinfo)
    SDL.copy renderer texture Nothing (Just $ SDL.Rectangle (SDL.P (coordinate st)) size)
    SDL.freeSurface surface
  go st (Clip size g) = do
    texture <- SDL.createTexture renderer SDL.RGBA8888 SDL.TextureAccessTarget size
    SDL.rendererRenderTarget renderer SDL.$= Just texture
    SDL.rendererDrawColor renderer SDL.$= clearColor
    SDL.clear renderer
    go (st { coordinate = SDL.V2 0 0 }) g
    SDL.rendererRenderTarget renderer SDL.$= Nothing
    SDL.copy renderer texture Nothing (Just $ SDL.Rectangle (SDL.P (coordinate st)) size)
  go st (ViewInfo v g) = cont st v >> go st g

empty :: Graphical
empty = Empty

text :: T.Text -> Graphical
text = Text

gridLayout :: SDL.Pos -> Graphical -> Graphical
gridLayout = GridLayout

rectangleWith :: IncludeAssoc ShapeStyle xs => Record xs -> SDL.Pos -> SDL.Pos -> Graphical
rectangleWith cfg = Rectangle (hmergeAssoc cfg defShapeStyle)
  where
    hmergeAssoc :: (IncludeAssoc ys xs, Wrapper h) => h :* xs -> h :* ys -> h :* ys
    hmergeAssoc hx hy = hfoldrWithIndex (\xin x hy -> hy & itemAt (hlookup xin inclusionAssoc) .~ x^._Wrapper) hy hx

rectangle :: SDL.Pos -> SDL.Pos -> Graphical
rectangle = rectangleWith nil

colored :: SDL.Color -> Graphical -> Graphical
colored = Colored

translate :: SDL.Pos -> Graphical -> Graphical
translate = Translate

graphics :: [Graphical] -> Graphical
graphics = Graphics

clip :: SDL.Pos -> Graphical -> Graphical
clip = Clip

viewInfo :: String -> Graphical -> Graphical
viewInfo = ViewInfo

