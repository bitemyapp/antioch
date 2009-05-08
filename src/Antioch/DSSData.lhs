> module Antioch.DSSData where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Score
> import Antioch.Utilities (hrs2rad, deg2rad, printList)
> import Data.List (groupBy, sort)
> import Data.Char (toUpper)
> import Database.HDBC
> import Database.HDBC.PostgreSQL

> connect :: IO Connection
> connect = handleSqlError $ connectPostgreSQL "dbname=dss_pmargani user=dss"

> getProjects :: IO [Project]
> getProjects = do
>     cnn <- connect
>     projs' <- fetchProjectData cnn
>     projs <- mapM (populateProject cnn) projs' 
>     return projs

> fetchProjectData :: Connection -> IO [Project]
> fetchProjectData cnn = handleSqlError $ do
>   result <- quickQuery' cnn query []
>   return $ toProjectDataList result
>     where
>       query = "SELECT projects.id, projects.pcode, semesters.semester, projects.thesis, allotment.total_time FROM semesters, allotment, projects, projects_allotments WHERE semesters.id = projects.semester_id AND projects.id = projects_allotments.project_id AND allotment.id = projects_allotments.allotment_id ORDER BY projects.pcode"
>       toProjectDataList = map toProjectData
>       toProjectData (id:pcode:semester:thesis:time:[]) = 
>         defaultProject {
>             pId = fromSql id 
>           , pName = fromSql pcode 
>           , semester = fromSql semester  
>           , thesis = fromSql thesis 
>           , timeTotal = (*60) $ fromSql time 
>         }

> populateProject :: Connection -> Project -> IO Project
> populateProject cnn project = do
>     sessions' <- getSessions (pId project) cnn
>     sessions <- mapM (populateSession cnn) sessions'
>     return $ makeProject project (timeTotal project) sessions

TBF: if a session is missing any of the tables in the below query, it won't
get picked up!!!

> getSessions :: Int -> Connection -> IO [Session]
> getSessions projId cnn = handleSqlError $ do 
>   result <- quickQuery' cnn query xs 
>   let ss' = toSessionDataList result
>   ss <- mapM (updateRcvrs cnn) ss'
>   return ss
>     where
>       query = "SELECT sessions.id, sessions.name, sessions.min_duration, sessions.max_duration, sessions.time_between, sessions.frequency, allotment.total_time, allotment.grade, targets.horizontal, targets.vertical, status.enabled, status.authorized, status.backup, session_types.type FROM sessions, allotment, targets, status, session_types WHERE allotment.id = sessions.allotment_id AND targets.session_id = sessions.id AND sessions.status_id = status.id AND sessions.session_type_id = session_types.id AND sessions.project_id = ?"
>       xs = [toSql projId]
>       toSessionDataList = map toSessionData
>       toSessionData (id:name:mind:maxd:between:freq:time:fltGrade:h:v:e:a:b:sty:[]) = 
>         defaultSession {
>             sId = fromSql id 
>           , sName = fromSql name
>           , frequency   = fromSql freq
>           , minDuration = (*60) $ fromSqlInt mind
>           , maxDuration = (*60) $ fromSqlInt maxd
>           , timeBetween = (*60) $ fromSqlInt between
>           , totalTime   = (*60) $ fromSql time 
>           , ra = hrs2rad . fromSql $ h -- TBF: assume all J200? For Carl's DB, YES!
>           , dec = deg2rad . fromSql $ v 
>           , grade = toGradeType fltGrade 
>           , receivers = [] -- TBF: does scoring support the logic structure!
>           , periods = [] -- TBF, no history in Carl's DB
>           , enabled = fromSql e
>           , authorized = fromSql a
>           , backup = fromSql b
>           , band = deriveBand $ fromSql freq
>           , sType = toSessionType sty
>         }
>        -- TBF: need to cover any other types?

Since the Session data structure does not support Nothing, when we get NULLs
from the DB (Carl didn't give it to us), then we need some kind of default
value of the right type.

> fromSqlInt SqlNull = 0
> fromSqlInt x       = fromSql x

TBF: is this totaly legit?  and should it be somewhere else?

> deriveBand :: Float -> Band
> deriveBand freq | freq <= 2.0                  = L
> deriveBand freq | freq > 2.00 && freq <= 3.95  = S
> deriveBand freq | freq > 3.95 && freq <= 5.85  = C
> deriveBand freq | freq > 5.85 && freq <= 8.00  = X
> deriveBand freq | freq > 8.00 && freq <= 10.0  = U
> deriveBand freq | freq > 12.0 && freq <= 15.4  = A
> deriveBand freq | freq > 18.0 && freq <= 26.0  = K
> deriveBand freq | freq > 26.0 && freq <= 40.0  = Q
> deriveBand freq | freq > 40.0 && freq <= 50.0  = S
> deriveBand freq | otherwise = W -- shouldn't get any of these!

> toSessionType :: SqlValue -> SessionType
> toSessionType val = read . toUpperFirst $ fromSql val
>   where
>     toUpperFirst x = [toUpper . head $ x] ++ tail x

> toGradeType :: SqlValue -> Grade
> toGradeType val = if (fromSql val) == (3.0 :: Float) then GradeA else GradeB 

Given a Session, find the Rcvrs for each Rcvr Group.
This is a separate func, and not part of the larger SQL in getSessions
in part because if there are *no* rcvrs, that larger SQL would not return
*any* result (TBF: this bug is still there w/ the tragets)

> updateRcvrs :: Connection -> Session -> IO Session
> updateRcvrs cnn s = do
>   rcvrGroups <- getRcvrGroups cnn s
>   cnfRcvrs <- mapM (getRcvrs cnn s) rcvrGroups
>   return $ s {receivers = cnfRcvrs}

> getRcvrGroups :: Connection -> Session -> IO [Int]
> getRcvrGroups cnn s = do
>   result <- quickQuery' cnn query xs 
>   return $ toRcvrGrpIds result
>   where
>     xs = [toSql . sId $ s]
>     query = "SELECT rg.id FROM receiver_groups AS rg WHERE rg.session_id = ?"
>     toRcvrGrpIds = map toRcvrGrpId 
>     toRcvrGrpId [x] = fromSql x

> getRcvrs :: Connection -> Session -> Int -> IO ReceiverGroup
> getRcvrs cnn s id = do
>   result <- quickQuery' cnn query xs 
>   return $ toRcvrList s result
>   where
>     xs = [toSql id]
>     query = "SELECT r.name FROM receivers as r, receiver_groups_receivers as rgr WHERE rgr.receiver_id = r.id AND rgr.receiver_group_id = ?"
>     toRcvrList s = map (toRcvr s)
>     toRcvr s [x] = toRcvrType s x

TBF: is what we'ere doing here w/ the rcvr and frequency legal?

> toRcvrType :: Session -> SqlValue -> Receiver
> toRcvrType s val = if (fromSql val) == ("Rcvr18_26" :: String) then findRcvr18_26 s else read . fromSql $ val
>   where
>     findRcvr18_26 s = if frequency s < 22.0 then Rcvr18_22 else Rcvr22_26 

> populateSession :: Connection -> Session -> IO Session
> populateSession cnn s = do
>     ps <- getPeriods cnn s
>     return $ makeSession s ps

> getPeriods :: Connection -> Session -> IO [Period]
> getPeriods cnn s = do
>     dbPeriods <- fetchPeriods cnn s 
>     optPeriods <- periodsFromOpts cnn s
>     return $ sort $ dbPeriods ++ optPeriods

TBF: no Period table in the DB yet.

> fetchPeriods :: Connection -> Session -> IO [Period]
> fetchPeriods cnn s = return []

Opportunities for Fixed Sessions should be honored via Periods

> periodsFromOpts :: Connection -> Session -> IO [Period]
> periodsFromOpts cnn s | sType s == Open = return [] 
>                       | sType s == Windowed = return [] 
>                       | sType s == Fixed = periodsFromOpts' cnn s

> periodsFromOpts' :: Connection -> Session -> IO [Period]
> periodsFromOpts' cnn s = do
>   result <- quickQuery' cnn query xs 
>   return $ toPeriodList result
>   where
>     xs = [toSql . sId $ s]
>     query = "SELECT opportunities.window_id, windows.required, opportunities.start_time, opportunities.duration FROM windows, opportunities where windows.id = opportunities.window_id and windows.session_id = ?"
>     toPeriodList = map toPeriod
>     toPeriod (wid:wreq:start:durHrs:[]) = 
>       defaultPeriod { startTime = fromSql start
>                     , duration = (*60) . fromSql $ durHrs
>                     }
