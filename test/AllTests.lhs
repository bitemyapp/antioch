Copyright (C) 2011 Associated Universities, Inc. Washington DC, USA.

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.

Correspondence concerning GBT software should be addressed as follows:
      GBT Operations
      National Radio Astronomy Observatory
      P. O. Box 2
      Green Bank, WV 24944-0002 USA

> module Antioch.AllTests where

> import qualified Antioch.DailyScheduleTests as DailyScheduleT
> import qualified Antioch.DateTimeTests as DateTimeT
> import qualified Antioch.DebugTests as DebugT
> import qualified Antioch.DSSDataTests as DSSDataT
> import qualified Antioch.DSSReversionTests as DSSReversionT
> import qualified Antioch.FilterTests as FilterTestT
> import qualified Antioch.GenerateScheduleTests as GeneratorT
> import qualified Antioch.HardwareScheduleTests as HardwareScheduleT
> import qualified Antioch.HistoricalWeatherTests as HistoricalWeatherT
> import qualified Antioch.PlotTests as PlotT
> import qualified Antioch.ReceiverTests as ReceiverT
> import qualified Antioch.ReceiverTemperaturesTests as ReceiverTempT
> import qualified Antioch.ReportsTests as ReportT
> import qualified Antioch.RunHistWeatherOptTests as RunHistWeatherOptT
> import qualified Antioch.RunDailyScheduleTests as RunDailyScheduleT
> import qualified Antioch.RunScoresTests as RunScoresT
> import qualified Antioch.ScheduleTests as ScheduleT
> import qualified Antioch.ScoreTests as ScoreT
> import qualified Antioch.SLAlibTests as SLAlibT
> import qualified Antioch.StatisticsTests as StatsT
> import qualified Antioch.SimulationTests as SimsT
> import qualified Antioch.Schedule.PackTests as PackT
> import qualified Antioch.TimeAccountingTests as TimeAccountingT
> import qualified Antioch.UtilitiesTests as UtilitiesT
> import qualified Antioch.WeatherTests as WeatherT
> import Test.HUnit

> tests = TestList [
>     DailyScheduleT.tests
>   , DateTimeT.tests
>   , PlotT.tests
>   , DebugT.tests
>   , DSSDataT.tests
>   , DSSReversionT.tests
>   , FilterTestT.tests
>   , HardwareScheduleT.tests
>   , HistoricalWeatherT.tests
>   , ScoreT.tests
>   , ScheduleT.tests
>   , RunScoresT.tests
>   , SLAlibT.tests
>   , StatsT.tests
>   , PackT.tests
>   , ReceiverT.tests
>   , ReceiverTempT.tests
>   , RunDailyScheduleT.tests
>   , RunHistWeatherOptT.tests
>   , TimeAccountingT.tests
>   , UtilitiesT.tests
>   , WeatherT.tests
>   , GeneratorT.tests
>   , ReportT.tests
>   , SimsT.tests  -- place longer tests at the end
>   ]

> main = do
>     runTestTT tests
