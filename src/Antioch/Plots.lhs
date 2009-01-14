> module Antioch.Plots where

> import Antioch.DateTime (DateTime)
> import Graphics.Gnuplot.Simple

> histStyle :: PlotStyle
> histStyle = PlotStyle Boxes (CustomStyle []) Nothing

> histogramPlot :: [(Float, Float)] -> IO ()
> histogramPlot = plotPathStyle [LogScale "y"] histStyle

> histogramPlots       :: [[(Float, Float)]] -> IO ()
> histogramPlots plots =
>     plotPathsStyle [LogScale "y"] [(histStyle, xys) | xys <- plots]

> scatterStyle :: PlotStyle
> scatterStyle = PlotStyle Points (CustomStyle []) Nothing

> scatterPlot :: [(Float, Float)] -> IO ()
> scatterPlot = plotPathStyle [] scatterStyle

> scatterPlots       :: [[(Float, Float)]] -> IO ()
> scatterPlots plots =
>     plotPathsStyle [] [(scatterStyle, xys) | xys <- plots]

> errorBarPlot :: [(Float, Float, Float)] -> IO ()
> errorBarPlot = plotErrorBars []