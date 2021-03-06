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

> module Antioch.ReportsTests where

> --import Antioch.Reports
> import Antioch.RunSimulation
> import Antioch.Reports
> import Antioch.Schedule
> import Test.HUnit
> import Antioch.Types
> import Antioch.DateTime
> import Antioch.Score
> import Antioch.PProjects
> import Antioch.GenerateSchedule
> import Data.List
> import Data.Maybe
> import System.Directory
> import System.Cmd

Main value of these unit tests is to check for compilation and run time errors:
If it doesn't blow up, it passes

> tests = TestList [ test_runSim
>                  , test_textReports
>                  , test_reportPeriodWindow
>                  , test_reportWindowedTimes
>                  , test_reportWindowedTimesByBand
>                  , test_reportWindowEfficiencies
>                  ]


> test_runSim = TestCase $ do
>   -- remove old plots
>   fs <- getFiles "." ".png"
>   cleanUpFiles fs
>   fs <- getFiles "." ".png"
>   assertEqual "test_runSim 1" 0 (length fs)
>   -- how many .txt files are there now?
>   originalTxtFiles <- getFiles "." ".txt"
>   let start = fromGregorian 2006 2 2 0 0 0
>   -- make sure test is true so that we use weather DB for tests
>   let test = True
>   runSimulation Pack start 3 False 100 0 0 2000 "." "" True True test
>   -- make sure new plots and text report are there
>   fs <- getFiles "." ".png"
>   -- how many plots did we make?
>   assertEqual "test_runSim" 44 (length fs)
>   finalTxtFiles <- getFiles "." ".txt"
>   assertEqual "test_runSim 2" 1 ((length finalTxtFiles) - (length originalTxtFiles))
>   -- clean up any simulation files
>   let simFiles = filter (\f -> (take 11 f) == "simulation_") finalTxtFiles
>   assertEqual "test_runSim 3" True (length simFiles >= 1) 
>   cleanUpFiles simFiles

> test_textReports = TestCase $ do
>     textReports name outdir now execTime dt days strategyName ss schedule canceled canceledDetails winfo we gaps scores scoreDetails simInput rs history quiet 
>     textReports name outdir now execTime dt days strategyName ss2 schedule2 canceled canceledDetails winfo we gaps scores scoreDetails simInput rs history quiet 
>   where
>     name = "unit_test"
>     outdir = "."
>     now = fromGregorian 2008 1 1 0 0 0
>     execTime = 100
>     dt = fromGregorian 2006 9 1 0 0 0
>     days = 70 
>     strategyName = "Pack"
>     ss = []
>     schedule = []
>     canceled = []
>     canceledDetails = []
>     gaps = []
>     scores = [("obsEff", [])
>             , ("atmEff", [])
>             , ("trkEff", [])
>             , ("srfEff", [])]
>     scoreDetails = [("obsEff", [])
>             , ("atmEff", [])
>             , ("trkEff", [])
>             , ("srfEff", [])]
>     simInput = True
>     rs = []
>     winfo = []
>     we = []
>     history = []
>     quiet = True
>     -- for the second report, use the test sessions
>     ss2 = getOpenPSessions
>     --s = head ss2'
>     --p = defaultPeriod { session = s
>     --                  , startTime = fromGregorian 2006 2 3 0 0 0
>     --                  , duration = 60
>     --                  }
>     --s' = makeSession s [] [p]
>     --ss2 = tail ss2' ++ [s']
>     schedule2 = concatMap periods ss2

> test_reportPeriodWindow = TestCase $ do
>     assertEqual "test_reportPeriodWindow_1" True (validSimulatedWindows s)
>     assertEqual "test_reportPeriodWindow_2" exp (reportPeriodWindow p)
>   where
>     {-
>     winStart = fromGregorian 2006 2 1 0 0 0
>     winDur   = 10*24*60
>     pStart   = fromGregorian 2006 2 8 5 30 0
>     s' = defaultSession { sType = Windowed }
>     p' = defaultPeriod { startTime = pStart
>                        , duration = 60*2 
>                        , session = s' }
>     w' = defaultWindow { wSession = s' 
>                        , wStart = winStart
>                        , wDuration = winDur }
>     s = makeSession s' [w'] [p']
>     -}
>     s = getTestWindowSession
>     p = head . periods $ s
>     exp = "2006-02-01 00:00:00                                   [2006-02-08 05:30:00 for 120 mins.] 2006-02-11 00:00:00\n"

> test_reportWindowedTimes = TestCase $ do
>     assertEqual "test_reportWindowedTimes_1" True (validSimulatedWindows s)
>     assertEqual "test_reportWindowedTimes_2" exp (reportWindowedTimes wInfo)
>     assertEqual "test_reportWindowedTimes_3" exp2 (reportWindowedTimes wInfo2)
>     assertEqual "test_reportWindowedTimes_4" exp3 (reportWindowedTimes (wInfo ++wInfo2))
>   where
>     s = getTestWindowSession
>     wInfo = [(head . windows $ s, Nothing, head . periods $ s)]
>     s2' = getTestWindowSession2
>     cp = defaultPeriod { session = s2
>                        , startTime = fromGregorian 2006 3 2 12 0 0
>                        , duration = 60*2 }
>     dp = head . periods $ s2'
>     s2 = makeSession s2' (windows s2') [cp]
>     wInfo2 = [(head . windows $ s2, Just cp, dp)]
>     exp = "Window Times:\n              Periods   Hours    \n    default   1         2.00     \n    chosen    0         0.00     \n    total     1         2.00     \n"
>     exp2 = "Window Times:\n              Periods   Hours    \n    default   0         0.00     \n    chosen    1         2.00     \n    total     1         2.00     \n"
>     exp3 = "Window Times:\n              Periods   Hours    \n    default   1         2.00     \n    chosen    1         2.00     \n    total     2         4.00     \n"

> test_reportWindowedTimesByBand = TestCase $ do
>     assertEqual "test_reportWindowedTimesByBand_1" True (validSimulatedWindows s)
>     assertEqual "test_reportWindowedTimesByBand_2" exp (reportWindowedTimesByBand wInfo)
>   where
>     s = getTestWindowSession
>     wInfo = [(head . windows $ s, Nothing, head . periods $ s)]
>     exp = "Window Times By Band: \n    Type     P         L         S         C         X         U         K         A         Q         W         \n    Default: 0.00      2.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      \n    Chosen : 0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      0.00      \n"

> test_reportWindowEfficiencies = TestCase $ do
>     let r = reportWindowEfficiencies winEffs
>     assertEqual "test_reportWindowEfficiencies_1" exp r
>   where
>     dt1 = fromGregorian 2006 2 1 0 0 0
>     dt2 = fromGregorian 2006 2 7 0 0 0
>     d1 = defaultPeriod { startTime = dt2, duration = 4*60 }
>     c1 = defaultPeriod { startTime = dt1, duration = 4*60 }
>     dt3 = fromGregorian 2006 3 1 0 0 0
>     dt4 = fromGregorian 2006 3 7 0 0 0
>     d2 = defaultPeriod { startTime = dt4, duration = 2*60 }
>     c2 = defaultPeriod { startTime = dt3, duration = 2*60 }
>     winEffs = [((c1,1.0),(d1,0.5)), ((c2,0.6),(d2,0.3))]
>     exp = "Window Period Efficiencies (Chosen vs. Default): \n    Chosen Mean Eff:  0.87     \n    Default Mean Eff: 0.43     \n    Period for     0 2006-02-01 00:00:00 for   240  mins. : 1.00      Period for     0 2006-02-07 00:00:00 for   240  mins. : 0.50     \n    Period for     0 2006-03-01 00:00:00 for   120  mins. : 0.60      Period for     0 2006-03-07 00:00:00 for   120  mins. : 0.30     \n"

Utilities:

> getFiles :: String -> String -> IO ([String])
> getFiles dir ext = do
>     allFiles <- getDirectoryContents "."
>     return $ filter isPngFile allFiles
>   where
>     isPngFile f = drop ((length f) - 4) f == ext

> cleanUpFiles :: [String] -> IO ()
> cleanUpFiles files = do
>     mapM system cmds
>     return ()
>   where
>     cmds = map ((++) "rm -rf ") files

> getTestWindowSession :: Session
> getTestWindowSession = makeSession s' [w'] [p']
>   where
>     winStart = fromGregorian 2006 2 1 0 0 0
>     winDur   = 10*24*60
>     pStart   = fromGregorian 2006 2 8 5 30 0
>     scheduled = fromGregorian 2006 2 8 0 0 0
>     s' = defaultSession { sType = Windowed , receivers = [[Rcvr1_2]], frequency = 2.0, band=L, grade=4.0, ra=3.7, dec=(-2.8)}
>     p' = defaultPeriod { startTime = pStart
>                        , duration = 60*2 
>                        , session = s'
>                        , pForecast = scheduled}
>     wr = [(winStart, addMinutes winDur winStart)]
>     w' = defaultWindow { wSession = s' 
>                        , wTotalTime = 60*2
>                        , wRanges = wr }

> getTestWindowSession2 :: Session
> getTestWindowSession2 = makeSession s' [w'] [p']
>   where
>     winStart = fromGregorian 2006 3 1 0 0 0
>     winDur   = 10*24*60
>     pStart   = fromGregorian 2006 3 8 5 30 0
>     s' = defaultSession { sType = Windowed, receivers = [[Rcvr1_2]], frequency = 2.0, band=L, grade=4.0, ra=3.7, dec=(-2.8) }
>     p' = defaultPeriod { startTime = pStart
>                        , duration = 60*2 
>                        , session = s' }
>     wr = [(winStart, addMinutes winDur winStart)]
>     w' = defaultWindow { wSession = s' 
>                        , wTotalTime = 60*2
>                        , wRanges = wr }

