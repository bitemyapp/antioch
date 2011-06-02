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

> tests = TestList [
>       test_fetchPeriods
>     , test_getWindows
>     , test_getPeriods
>     , test_getProjects
>     -- , test_numPeriods
>     , test_getProjectData
>     -- , test_getProjectsProperties
>     -- , test_putPeriods
>     -- , test_movePeriodsToDeleted
>     -- , test_populateWindowedSession
>     , test_makeSession
>     , test_scoreDSSData
>     , test_session2
>     , test_sessionGal
>     , test_session_scores
>     , test_totaltime
>     , test_toDateRangesFromInfo_1
>     , test_toDateRangesFromInfo_2
>     , test_toDateRangesFromInfo_3
>     ]

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
>     let ss' = reverse . tail $ reverse ss
>     let allPeriods = sort $ concatMap periods $ ss
>     assertEqual "test_getProjects1" 1 (length ps)  
>     assertEqual "test_getProjects5" 1 (pId . head $ ps)  
>     assertEqual "test_getProjects5" 1 (pId . head $ ps)  
>     assertEqual "test_getProjects2" "GBT09A-001" (pName . head $ ps)  
>     assertEqual "test_getProjects3" 0 (pAllottedT . head $ ps)  
>     assertEqual "test_getProjects4" 4 (length . sessions . head $ ps)  
>     assertEqual "test_getProjects8" Open (sType . head $ ss)
>     assertEqual "test_getProjects6" 1 (pId . project . head $ ss)    
>     assertEqual "test_getProjects7" 1 (length . nub $ map (pId . project) $ ss) 
>     assertEqual "test_getProjects9" [] (dropWhile (/=W) (map band ss))    
>     assertEqual "test_getProjects10" 6 (length allPeriods)    
>     assertEqual "test_getProjects11" [[Rcvr8_10]] (receivers . head $ ss)
>     assertEqual "test_getProjects12" True (guaranteed . head $ ss)
>     assertEqual "test_getProjects13" 1 (length . electives . last $ ss')
>     assertEqual "test_getProjects14" [5,6] (ePeriodIds . head . electives . last $ ss')
>     assertEqual "test_getProjects15" 1 (length . observers . head $ ps)
>     assertEqual "test_getProjects16" 1 (length . requiredFriends . head $ ps)
>     assertEqual "test_getProjects17" obsBlackouts ( blackouts . head . observers . head $ ps) 
>     assertEqual "test_getProjects18" frdBlackouts ( blackouts . head . requiredFriends . head $ ps) 
>   where
>     obsBlackouts = [(fromGregorian 2009 4 1 0 0 0,fromGregorian 2009 4 3 0 0 0)]    
>     frdBlackouts = [(fromGregorian 2009 4 7 0 0 0,fromGregorian 2009 4 10 0 0 0)]    

TBF: cant' run this one automatically because it doesn't clean up yet, 
so, clean up by hand for now.

> test_numPeriods = TestCase $ do
>   projs <- getProjects
>   let ps = concatMap periods $ concatMap sessions projs
>   let numPs = length ps
>   assertEqual "test_numPeriods_1" 137 numPs
>   --  now create a new period identical to an existing period
>   -- and make sure it doesn't get translated to a period
>   assertEqual "test_numPeriods_2" [identicalToOpt] (filter (==identicalToOpt) ps)
>   -- TBF: Oops!  We're supposed to put in a new opportunity, not a window!
>   --putPeriods [identicalToOpt]
>   projs <- getProjects
>   let ps = concatMap periods $ concatMap sessions projs
>   assertEqual "test_numPeriods_3" numPs (length ps)
>   -- need to clean up!
>     where
>       identicalToOpt = defaultPeriod { session = defaultSession { sId = 48 }
>                             , startTime = fromGregorian 2009 7 15 4 0 0
>                             , duration = hrsToMinutes 3.75 
>                             , pForecast = fromGregorian 2009 7 15 4 0 0
>                                      }
>   

Makes sure that a project with hrs for more then one grade is imported
once and has a total time that is the sum of the grade hrs.

> test_totaltime = TestCase $ do
>   projs <- getProjects
>   let ps = filter (\p -> (pName p) == "GBT09A-001") projs
>   assertEqual "test_sAllottedT_1" 1 (length ps)
>   assertEqual "test_sAllottedT_2" 0 (pAllottedT . head $ ps)

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
>       expScores = [0.0,0.71830034,0.723035,0.72897196,0.7306815,0.73508745,0.7376189,0.73988056,0.7450153,0.7467272,0.7482739,0.74967504,0.74223655,0.74284345,0.74342054,0.74397194,0.7436074]

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

> test_sessionGal = TestCase $ do
>   ps <- getProjects 
>   let ss = concatMap sessions ps
>   let s = head $ filter (\s -> (sName s == "GBT09A-001-Gal")) ss
>   assertEqual "test_sessionGal_1" 3.0 (grade s)
>   assertEqual "test_sessionGal_2" Open (sType s)
>   assertEqual "test_sessionGal_3" 4 (sId s)
>   assertEqual "test_sessionGal_4" "GBT09A-001-Gal" (sName s)
>   assertEqual "test_sessionGal_5" "GBT09A-001" (pName . project $ s)
>   assertEqual "test_sessionGal_6" "09A" (semester . project $ s)
>   assertEqual "test_sessionGal_7" 210 (sAllottedT s)
>   assertEqual "test_sessionGal_8" 180 (minDuration s)
>   assertEqual "test_sessionGal_9" 210 (maxDuration s)
>   assertEqual "test_sessionGal_10" 0 (timeBetween s)
>   assertEqual "test_sessionGal_11" 9.3 (frequency s)
>   assertEqual "test_sessionGal_12" 4.4592996  (ra s)
>   assertEqual "test_sessionGal_13" (-0.91732764) (dec s)
>   assertEqual "test_sessionGal_14" [[Rcvr8_10]] (receivers s)
>   assertEqual "test_sessionGal_15" X (band s)
>   assertEqual "test_sessionGal_16" False (lowRFI s)
>   assertEqual "test_sessionGal_17" 1 (length . lstExclude $ s)

Perhaps these should be Quick Check properities, but the input is not 
generated: it's the input we want to test, really.

> test_getProjectsProperties = TestCase $ do
>   ps <- getProjects
>   let ss = concatMap sessions ps
>   let allPeriods = sort $ concatMap periods ss 
>   assertEqual "test_getProjects_properties_1" True (all validProject ps)  
>   assertEqual "test_getProjects_properties_2" True (all validSession ss)  
>   assertEqual "test_getProjects_properties_3" True (validPeriods allPeriods)  
>   assertEqual "test_getProjects_properties_4" True (2 < length (filter (\s -> grade s == 3.0) ss) )
>   assertEqual "test_getProjects_properties_5" 46 (length $ filter lowRFI ss)
>   let lsts = filter (\s -> (length . lstExclude $ s) > 0) ss
>   assertEqual "test_getProjects_properties_6" 4 (length lsts)
>   assertEqual "test_getProjects_properties_7" [(15.0,21.0)] (lstExclude . head $ lsts)
>   assertEqual "test_getProjects_properties_8" [(14.0,9.0)] (lstExclude . last $ lsts)
>   -- TBF, BUG: Session (17) BB261-01 has no target, 
>   -- so is not getting imported.
>   assertEqual "test_getProjects_properties_9" 255 (length ss)  
>   assertEqual " " True True
>     where
>       validProject proj = "0" == (take 1 $ semester proj)
>       validSession s = (maxDuration s) >= (minDuration s)
>                    -- TBF!! &&  (sAllottedT s)     >= (minDuration s)
>                     &&  (validRA s) && (validDec s)
>       validPeriods allPeriods = not . internalConflicts $ allPeriods

> test_putPeriods = TestCase $ do
>   r1 <- getNumRows "periods"
>   putPeriods [p1]
>   r2 <- getNumRows "periods"
>   cleanup "periods"
>   assertEqual "test_putPeriods" True (r2 == (r1 + 1)) 
>     where
>       dt = fromGregorian 2006 1 1 0 0 0
>       p1 = defaultPeriod { session = defaultSession { sId = 1 }
>                          , startTime = dt
>                          , pScore = 0.0
>                          , pForecast = dt }

> test_movePeriodsToDeleted = TestCase $ do
>   projs <- getProjects
>   let ps = concatMap periods $ concatMap sessions projs
>   let exp = [Pending,Scheduled,Pending,Pending]
>   assertEqual "test_movePeriods_1" exp (map pState ps) 
>   -- move all to deleted
>   movePeriodsToDeleted ps
>   projs <- getProjects
>   let ps = concatMap periods $ concatMap sessions projs
>   --let exp = [Deleted,Deleted,Deleted,Deleted]
>   -- won't pick them up from DB since they are deleted
>   assertEqual "test_movePeriods_2" [] ps 
>   -- move them back
>   cnn <- connect
>   movePeriodToState cnn 1 1 
>   movePeriodToState cnn 2 2 
>   movePeriodToState cnn 3 1 
>   movePeriodToState cnn 4 1 
>   -- make sure the moved back okay
>   projs <- getProjects
>   let ps = concatMap periods $ concatMap sessions projs
>   assertEqual "test_movePeriods_3" exp (map pState ps) 

Kluge, data base has to be prepped manually for test to work, see
example in comments.

> test_populateWindowedSession = TestCase $ do
>   cnn <- connect
>   s <- getSession sId cnn
>   ios <- populateSession cnn s
>   assertEqual "test_populateWindowedSession 1" s ios
>     where
>       sId =  194  -- just placeholders
>       pId = 1760

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

