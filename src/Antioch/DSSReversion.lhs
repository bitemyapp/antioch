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

> module Antioch.DSSReversion where

> import Antioch.DateTime
> import Antioch.Types
> import Antioch.Score
> import Antioch.Settings                (dssDataDB)
> import Antioch.Utilities
> import Control.Monad.Trans             (liftIO)
> import Data.List                       (sort, nub, find)
> import Data.Char                       (toUpper)
> import Database.HDBC
> import Database.HDBC.PostgreSQL

This module is responsible for keep keeping our change tracking up to date:
Nell uses the django-reversion package for change tracking: it keeps track of
changes to objects as long as those changes happen in nell (django).  But here
in Antioch we write periods to the DB - so if we want to track that, we need
to do what the django-reversion package does down at the DB level.

In practice, this means filling out the reversion_revision and reversion_version
tables in the correct manner.

> putPeriodReversion :: Connection -> Period -> Int -> Int -> IO ()
> putPeriodReversion cnn p accntId stateId = do
>     -- make a new reversion_revision entry
>     -- and get it's ID
>     revisionId <- putPeriodRevision cnn
>     -- make an entry for the period accounting table
>     putPeriodAccountingVersion cnn p revisionId accntId
>     -- make an entry for the period table
>     putPeriodVersion cnn p revisionId accntId stateId
>     return ()

Create a new revision entry that marks a change for right now, due to 
Antioch.DSSData.putPeriod.  Then each piece of info about the new period
is associated w/ this new revision.

> putPeriodRevision :: Connection -> IO (Int)
> putPeriodRevision cnn = do 
>     now <- getCurrentTime
>     -- add the time zone to the current time string
>     let nowStr = (toSqlString now) ++ "-04"
>     quickQuery' cnn query (xs nowStr)
>     commit cnn
>     revisionId <- getNewestID cnn "reversion_revision"
>     return revisionId
>   where
>     query = "INSERT INTO reversion_revision (date_created, user_id, comment) VALUES (?, NULL, ?)"
>     comment = "WHO: antioch WHERE: putPeriod"
>     xs nowStr = [toSql nowStr, toSql comment]

There are a few objects associated with the newly created revision:
   * period
   * period_accounting

Here we take the period we wrote to the DB and mimic what would have been put
in the reversion_version table if it had been created in Django:

> putPeriodAccountingVersion :: Connection -> Period -> Int -> Int -> IO ()
> putPeriodAccountingVersion cnn p revisionId accntId = do
>     quickQuery' cnn query xs
>     commit cnn
>   where
>     query = "INSERT INTO reversion_version (revision_id, object_id, content_type_id, format, serialized_data, object_repr, type) VALUES (?, ?, 80, 'json', ?, ?, 1)"
>     serialData = serializePeriodAccounting p accntId
>     objRepr = representPeriodAccounting p accntId
>     xs = [toSql revisionId, toSql accntId, toSql serialData, toSql objRepr]

This should replicate the django.core.serialize product for a Period.

> putPeriodVersion :: Connection -> Period -> Int -> Int -> Int -> IO ()
> putPeriodVersion cnn p revisionId accntId stateId = do
>     quickQuery' cnn query xs
>     commit cnn
>   where
>     query = "INSERT INTO reversion_version (revision_id, object_id, content_type_id, format, serialized_data, object_repr, type) VALUES (?, ?, 59, 'json', ?, ?, 1)"
>     serialData = serializePeriod p accntId stateId
>     objRepr = representPeriod p
>     xs = [toSql revisionId, toSql . peId $ p, toSql serialData, toSql objRepr]

This should replicate the django.core.serialize product for a Period.
Example:
 serializePeriod p = "[{\"pk\": 3685, \"model\": \"sesshuns.period\", \"fields\": {\"score\": 66.0, \"moc_ack\": false, \"forecast\": \"2010-03-23 17:30:00\", \"start\": \"2010-03-23 00:00:00\", \"state\": 1, \"session\": 339, \"duration\": 1.0, \"accounting\": 4099, \"backup\": false}}]"

> serializePeriod :: Period -> Int -> Int -> String
> serializePeriod p accntId stateId =  "[{\"pk\": " ++ pk ++ ", \"model\": \"scheduler.period\", \"fields\": {\"score\": " ++ sc ++ ", \"moc_ack\": " ++ moc ++ ", \"forecast\": \"" ++ forecast ++ "\", \"start\": \"" ++ start ++ "\", \"state\": " ++ state ++ ", \"session\": " ++ sessionId ++ ", \"duration\": " ++ dur ++ ", \"accounting\": " ++ accountingId ++ ", \"backup\": " ++ backup ++ "}}]"
>   where
>     pk = show . peId $ p
>     sc = show . pScore $ p
>     moc = "false" -- We can hardcode this because it's a new period!
>     forecast = toSqlString . pForecast $ p
>     start = toSqlString . startTime $ p
>     state = show stateId 
>     sessionId = show . sId . session $ p
>     dur = show . duration $ p
>     accountingId = show accntId 
>     backup = toSqlBool . pBackup $ p 



This should replicate the django.core.serialize product for a Period_Accounting.
Example:
[{"pk": 4099, "model": "sesshuns.period_accounting", "fields": {"scheduled": 0.0, "other_session_rfi": 0.0, "description": null, "other_session_weather": 0.0, "lost_time_other": 0.0, "short_notice": 0.0, "not_billable": "0", "lost_time_weather": 0.0, "other_session_other": 0.0, "lost_time_rfi": 0.0}}]

This method is very simple since a newly created pending period had no 
interesting information in it's time accounting yet.

> serializePeriodAccounting :: Period -> Int -> String
> serializePeriodAccounting p accntId = "[{\"pk\": " ++ (show accntId) ++ ", \"model\": \"scheduler.period_accounting\", \"fields\": {\"scheduled\": 0.0, \"other_session_rfi\": 0.0, \"description\": null, \"other_session_weather\": 0.0, \"lost_time_other\": 0.0, \"short_notice\": 0.0, \"not_billable\": \"0\", \"lost_time_weather\": 0.0, \"other_session_other\": 0.0, \"lost_time_rfi\": 0.0}}]"

This should replicate the __str__ method for the Django Period_Accounting Model:
Example:
Id (4099); SC: 0.00 OT: 0.00 NB: 0.00 OS: 0.00 LT: 0.00 SN: 0.00

> representPeriodAccounting :: Period -> Int -> String
> representPeriodAccounting p accntId = "Id (" ++ (show accntId) ++ "); SC: 0.00 OT: 0.00 NB: 0.00 OS: 0.00 LT: 0.00 SN: 0.00"


Need this special function because Show Bool gives "True" and "False"

> toSqlBool :: Bool -> String
> toSqlBool bool = if bool then "true" else "false"

This should replicate the __str__ method for the Django Period Model:

> representPeriod :: Period -> String
> representPeriod p = "Period for Session (" ++ id ++ "): " ++ start ++ " for " ++ dur ++ " Hrs (" ++ state ++ ")"
>   where
>     id = show . peId $ p
>     start = show . toSqlString . startTime $ p
>     dur = show $ (fromIntegral . duration $ p) / 60.0
>     state = show. head . show . pState $ p -- ex: 'P', 'S', ...

Utilities

What's the largest (i.e. newest) primary key in the given table?

> getNewestID :: Connection -> String -> IO Int
> getNewestID cnn table = do
>     r <- quickQuery' cnn query xs
>     return $ toId r
>   where
>     xs = [] 
>     query = "SELECT MAX(id) FROM " ++ table
>     toId [[x]] = fromSql x
