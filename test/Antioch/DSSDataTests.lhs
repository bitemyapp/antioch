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

> module Antioch.DSSDataTests where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Weather (getWeatherTest)
> import Antioch.Score
> import Antioch.DSSData
> import Antioch.Utilities
> import Antioch.ReceiverTemperatures (getRT)
> import Antioch.Generators (internalConflicts, internalConflicts', validRA, validDec)
> import Maybe
> import List (nub, sort)
> import Data.List (find)
> import Test.HUnit
> import Control.Monad.Trans                   (liftIO)
> import System.IO.Unsafe (unsafePerformIO)
> import Database.HDBC

The DB used for these unit tests is created and populated via the
instructions in admin/genDssTestDatagase.py.

Note that all these tests are read only.  There are no unit tests
for functions that write to the DB because not only does that 
corrupt the DB for the next test, but we also have problems resetting
the DB connection.
Story: https://www.pivotaltracker.com/story/show/14123905

> tests = TestList [
>       test_fetchPeriods
>     , test_getWindows
>     , test_getPeriods
>     , test_getPeriodStates
>     , test_getPeriodStateId
>     , test_getProjects
>     , test_getProjectData
>     , test_makeSession
>     , test_scoreDSSData
>     , test_session2
>     , test_session_scores
>     , test_totaltime
>     , test_toDateRangesFromInfo_1
>     , test_toDateRangesFromInfo_2
>     , test_toDateRangesFromInfo_3
>     ]

> test_getPeriodStates = TestCase $ do
>     cnn <- connect
>     states <- getPeriodStates cnn
>     assertEqual "test_getPeriodStates" expectedPeriodStates states 

> test_getPeriodStateId = TestCase $ do
>     assertEqual "test_getPeriodStateId 1" 1 (getState Pending)
>     assertEqual "test_getPeriodStateId 2" 2 (getState Scheduled)
>     assertEqual "test_getPeriodStateId 3" 3 (getState Deleted)
>     assertEqual "test_getPeriodStateId 4" 4 (getState Complete)
>   where
>     getState st = getPeriodStateId st expectedPeriodStates

> test_getProjectData = TestCase $ do
>     cnn <- connect
>     d <- fetchProjectData cnn
>     assertEqual "test_getProjectData1" 1 (length d)  
>     assertEqual "test_getProjectData2" "GBT09A-001" (pName . head $ d)  
>     assertEqual "test_getProjectData3" False (thesis . head $ d)  
>     disconnect cnn

> test_getProjects = TestCase $ do
>     ps <- getProjects 
>     let ss = concatMap sessions ps
>     let allPeriods = sort $ concatMap periods $ ss
>     assertEqual "test_getProjects1" 1 (length ps)  
>     assertEqual "test_getProjects5" 1 (pId . head $ ps)  
>     assertEqual "test_getProjects5" 1 (pId . head $ ps)  
>     assertEqual "test_getProjects2" "GBT09A-001" (pName . head $ ps)  
>     assertEqual "test_getProjects3" 6000 (pAllottedT . head $ ps)  
>     assertEqual "test_getProjects4" 4 (length . sessions . head $ ps)  
>     assertEqual "test_getProjects8" Open (sType . head $ ss)
>     assertEqual "test_getProjects6" 1 (pId . project . head $ ss)    
>     assertEqual "test_getProjects7" 1 (length . nub $ map (pId . project) $ ss) 
>     assertEqual "test_getProjects9" [] (dropWhile (/=W) (map band ss))    
>     assertEqual "test_getProjects10" 6 (length allPeriods)    
>     assertEqual "test_getProjects11" [[Rcvr8_10]] (receivers . head $ ss)
>     assertEqual "test_getProjects12" True (guaranteed . head $ ss)
>     let elecS = ss!!2
>     assertEqual "test_getProjects13" 1 (length . electives $ elecS)
>     assertEqual "test_getProjects14" [5,6] (ePeriodIds . head . electives $ elecS)
>     assertEqual "test_getProjects15" 1 (length . observers . head $ ps)
>     assertEqual "test_getProjects16" 1 (length . requiredFriends . head $ ps)
>     assertEqual "test_getProjects17" obsBlackouts ( blackouts . head . observers . head $ ps) 
>     assertEqual "test_getProjects18" frdBlackouts ( blackouts . head . requiredFriends . head $ ps) 
>   where
>     obsBlackouts = [(fromGregorian 2009 4 1 0 0 0,fromGregorian 2009 4 3 0 0 0)]    
>     frdBlackouts = [(fromGregorian 2009 4 7 0 0 0,fromGregorian 2009 4 10 0 0 0)]    

Makes sure that a project with hrs for more then one grade is imported
once and has a total time that is the sum of the grade hrs.

> test_totaltime = TestCase $ do
>   projs <- getProjects
>   let ps = filter (\p -> (pName p) == "GBT09A-001") projs
>   assertEqual "test_sAllottedT_1" 1 (length ps)
>   assertEqual "test_sAllottedT_2" 6000 (pAllottedT . head $ ps)

Makes sure that there is nothing so wrong w/ the import of data that a given
session scores zero through out a 24 hr period.

> test_scoreDSSData = TestCase $ do
>     w <- getWeatherTest . Just $ starttime 
>     rt <- getRT
>     ps <- getProjects
>     let ss = concatMap sessions ps
>     let sess' = fromJust . find (\s -> (sType s) == Open) $ ss
>     let score' w dt = runScoring w [] rt $ do
>         fs <- genScore starttime ss 
>         s <- fs dt sess'
>         return $ eval s
>     scores <- mapM (score' w) times
>     let nonZeros = filter (/= 0.0) scores
>     assertEqual "test_scoreDSSData" True ((length nonZeros) /= 0)
>   where
>     starttime = fromGregorian 2006 11 8 12 0 0
>     times = [(15*q) `addMinutes` starttime | q <- [0..96]]

How a session scores can also reveal errors in how it was imported
from the database.

> test_session_scores = TestCase $ do
>     w <- getWeatherTest $ Just start
>     rt <- getRT
>     ps <- getProjects
>     let ss = concatMap sessions ps
>     -- get the session and give it an observer
>     let s' = head $ filter (\s -> (sName s) == name) ss
>     let p' = project s'
>     let p = p' { observers = [defaultObserver] }
>     let s = s' { project = p }
>     let score' w dt = runScoring w [] rt $ do
>         fs <- genScore start ss 
>         sf <- fs dt s
>         return $ eval sf
>     scores <- mapM (score' w) times
>     assertEqual "test_session_scores" expScores scores
>     where
>       name = "GBT09A-001-02"
>       --start = fromGregorian 2006 6 6 3 0 0 -- 11 PM ET
>       start = fromGregorian 2006 6 6 6 30 0
>       times = [(15*q) `addMinutes` start | q <- [0..16]]
>       expScores = [0.0,1.0626621,1.0696664,1.0784497,1.0809788,1.087497,1.0912421,1.094588,1.1021845,1.1047171,1.1070054,1.1090782,1.0980735,1.0989712,1.099825,1.1006408,1.1001016]

Test a specific session's attributes:

> test_session2 = TestCase $ do
>   ps <- getProjects 
>   let ss = concatMap sessions ps
>   let s = head $ filter (\s -> (sName s == "GBT09A-001-02")) ss
>   assertEqual "test_session2_1" 3.0 (grade s)
>   assertEqual "test_session2_2" Open (sType s)
>   assertEqual "test_session2_3" 1 (sId s)
>   assertEqual "test_session2_4" "GBT09A-001-02" (sName s)
>   assertEqual "test_session2_5" "GBT09A-001" (pName . project $ s)
>   assertEqual "test_session2_6" "09A" (semester . project $ s)
>   assertEqual "test_session2_7" 210 (sAllottedT s)
>   assertEqual "test_session2_8" 180 (minDuration s)
>   assertEqual "test_session2_9" 210 (maxDuration s)
>   assertEqual "test_session2_10" 0 (timeBetween s)
>   assertEqual "test_session2_11" 9.3 (frequency s)
>   assertEqual "test_session2_12" 5.861688  (ra s)
>   assertEqual "test_session2_13" (-0.11362094) (dec s)
>   assertEqual "test_session2_14" [[Rcvr8_10]] (receivers s)
>   assertEqual "test_session2_15" X (band s)
>   assertEqual "test_session2_16" False (lowRFI s)
>   assertEqual "test_session2_17" 1 (length . lstExclude $ s)

> mkSqlLst  :: Int -> DateTime -> Int -> Int -> Int -> Int -> String -> [SqlValue]
> mkSqlLst id strt dur def per pid st =
>     [toSql id
>    , toSql . toSqlString $ strt
>    , toSql dur
>    , if def == 0
>      then SqlNull
>      else toSql def
>    , if per == 0
>      then SqlNull
>      else toSql def
>    , toSql pid
>    , toSql st
>     ]

> test_makeSession = TestCase $ do
>   let s = makeSession s' [w'] [p']
>   assertEqual "test_makeSession 1" s' s
>   assertEqual "test_makeSession 2" s (session . head . periods $ s)
>   assertEqual "test_makeSession 3" p' (head . periods $ s)
>   assertEqual "test_makeSession 4" (Just p') (wPeriod . head . windows $ s)
>   assertEqual "test_makeSession 5" (head . periods $ s) (fromJust . wPeriod . head . windows $ s)
>     where
>       s' = defaultSession { sAllottedT = (8*60) }
>       p' = defaultPeriod { duration = (4*60) }
>       wr = [(defaultStartTime, addMinutes 7 defaultStartTime)]
>       w' = defaultWindow { wRanges = wr, wPeriodId = Just . peId $ p' }

> test_getWindows = TestCase $ do
>   cnn <- connect
>   s <- getSession 2 cnn
>   results <- getWindows cnn s
>   assertEqual "test_getWindows_1" 1 (length results)
>   assertEqual "test_getWindows_2" (6*60) (wTotalTime . head $ results)
>   assertEqual "test_getWindows_3" False (wComplete . head $ results)

> test_getPeriods = TestCase $ do
>   cnn <- connect
>   s <- getSession 1 cnn
>   ps' <- getPeriods cnn s
>   -- note fetchPeriods doesn't set the period's session
>   let ps = [defaultPeriod { session = defaultSession 
>                           , startTime = dt
>                           , duration = 240}]
>   disconnect cnn
>   assertEqual "test_getPeriods" ps ps'
>     where
>       dt = fromGregorian 2006 1 1 0 0 0

> test_fetchPeriods = TestCase $ do
>   cnn <- connect
>   s <- getSession 1 cnn
>   ps' <- fetchPeriods cnn s
>   -- note fetchPeriods doesn't set the period's session
>   let ps = [defaultPeriod { session = defaultSession
>                           , startTime = dt
>                           , duration = 240}]
>   disconnect cnn
>   assertEqual "test_fetchPeriods" ps ps' 
>     where
>       dt = fromGregorian 2006 1 1 0 0 0

> fromFloat2Sql :: Float ->  SqlValue
> fromFloat2Sql = toSql

> test_toDateRangesFromInfo_1 = TestCase $ do
>   let dtrs = toDateRangesFromInfo start end repeat until 
>   assertEqual "test_toDateRangesFromInfo_1" [(start, end)] dtrs
>     where
>       start = fromGregorian 2009 1 1 0 0 0
>       end   = fromGregorian 2009 1 1 4 0 0
>       until = fromGregorian 2009 1 1 4 0 0
>       repeat = "Ounce" 
>     

> test_toDateRangesFromInfo_2 = TestCase $ do
>   let dtrs = toDateRangesFromInfo start end repeat until 
>   assertEqual "test_toDateRangesFromInfo_2" exp dtrs
>     where
>       start = fromGregorian 2009 1 1 0 0 0
>       end   = fromGregorian 2009 1 1 4 0 0
>       until = fromGregorian 2009 1 23 0 0 0
>       repeat = "Weekly" 
>       exp = [(start, end)
>            , (fromGregorian 2009 1 8 0 0 0
>            ,  fromGregorian 2009 1 8 4 0 0)
>            , (fromGregorian 2009 1 15 0 0 0
>            ,  fromGregorian 2009 1 15 4 0 0)
>            , (fromGregorian 2009 1 22 0 0 0
>            ,  fromGregorian 2009 1 22 4 0 0)
>             ]

> test_toDateRangesFromInfo_3 = TestCase $ do
>   let dtrs = toDateRangesFromInfo start end repeat until 
>   assertEqual "test_toDateRangesFromInfo_3" exp dtrs
>     where
>       start = fromGregorian 2009 11  2 0 0 0
>       end   = fromGregorian 2009 11  2 4 0 0
>       until = fromGregorian 2010  2 23 0 0 0
>       repeat = "Monthly" 
>       exp = [(start, end)
>            , (fromGregorian 2009 12 2 0 0 0
>            ,  fromGregorian 2009 12 2 4 0 0)
>            , (fromGregorian 2010  1 2 0 0 0
>            ,  fromGregorian 2010  1 2 4 0 0)
>            , (fromGregorian 2010  2 2 0 0 0
>            ,  fromGregorian 2010  2 2 4 0 0)
>             ]

> test_addLSTExclusion = TestCase $ do
>   cnn <- connect
>   s <- getSession 1 cnn
>   let mod_s  = addLSTExclusion' True s single
>   let lstEx  = lstExclude mod_s
>   assertEqual "test_addLSTExclusion" lstEx lstEx'

>   let mod_s      = addLSTExclusion' True s range
>   let lstExRange = lstExclude mod_s
>   disconnect cnn
>   assertEqual "test_addLSTExclusion" lstExRange lstEx''
>     where
>       single = [[toSql "LST Exclude Low", toSql "1.0"], [toSql "LST Exclude Hi", toSql "3.0"]]
>       range  = [[toSql "LST Exclude Low", toSql "1.0"], [toSql "LST Exclude Hi", toSql "3.0"]
>               , [toSql "LST Exclude Low", toSql "6.0"], [toSql "LST Exclude Hi", toSql "9.0"]
>                 ]
>       lstEx'  = [(1.0, 3.0)]
>       lstEx'' = [(1.0, 3.0), (6.0, 9.0)]

> test_invertIn = TestCase $ do
>   let result = invertIn [] []
>   assertEqual "test_invertIn empty" [] result
>   let result = invertIn [2] [6]
>   assertEqual "test_invertIn single" [(0.0,2.0),(6.0,24.0)] result
>   let result = invertIn [0] [6]
>   assertEqual "test_invertIn single zero" [(6.0,24.0)] result
>   let result = invertIn [6, 12] [10, 14]
>   assertEqual "test_invertIn multiple" [(0.0,6.0),(10.0,12.0),(14.0,24.0)] result
>   let result = invertIn [0, 12] [10, 24]
>   assertEqual "test_invertIn multiple" [(10.0,12.0)] result

Test Utilities: 

> getNumRows :: String -> IO Int
> getNumRows tableName = do 
>     cnn <- connect
>     r <- quickQuery' cnn ("SELECT * FROM " ++ tableName) []
>     disconnect cnn
>     return $ length r

> cleanup :: String -> IO () 
> cleanup tableName = do
>     cnn <- connect
>     run cnn ("TRUNCATE TABLE " ++ tableName ++ " CASCADE") []
>     commit cnn
>     disconnect cnn

> expectedPeriodStates :: [(Int, StateType)]
> expectedPeriodStates = [(1,Pending),(2,Scheduled),(3,Deleted),(4,Complete)]

