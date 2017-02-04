<%@ WebService Language="C#" Class="Nikse.dk.SeService" %>
using System;
using System.Collections.Generic;
using System.Web.Caching;
using System.Web.Services;


namespace Nikse.dk
{
    [WebService(Namespace = "http://tempuri.org/")]
    [WebServiceBinding(ConformsTo = WsiProfiles.BasicProfile1_1)]
    [System.ComponentModel.ToolboxItem(false)]
    public class SeService : System.Web.Services.WebService
    {

        const int MinuteTimeOut = 10;

        public class SeSequence
        {
            public int Index;
            public int StartMilliseconds;
            public int EndMilliseconds;
            public string Text;

            public SeSequence()
            {
            }

            public SeSequence(int index, int startMilliseconds, int endMilliseconds, string text)
            {
                Index = index;
                StartMilliseconds = startMilliseconds;
                EndMilliseconds = endMilliseconds;
                Text = text;
            }
        }

        public class SeUser
        {
            public string UserName;
            public string Ip;
            public DateTime LastActivity;

            public SeUser()
            {
            }

            public SeUser(string userName, string ip)
            {
                UserName = userName;
                Ip = ip;
                LastActivity = DateTime.Now;
            }
        }

        public class SeUpdate
        {
            public DateTime Time;
            public SeUser User;
            public int Index;
            public int StartMilliseconds;
            public int EndMilliseconds;
            public string Text;
            public string Action;

            public SeUpdate()
            {
            }

            public SeUpdate(SeUser user, int index, int startMilliseconds, int endMilliseconds, string text, string action)
            {
                User = user;
                Index = index;
                StartMilliseconds = startMilliseconds;
                EndMilliseconds = endMilliseconds;
                Text = text;
                Action = action;
                Time = DateTime.Now;
            }
        }

        public class SeSession
        {
            public DateTime Started;
            public string Id;
            public string FileName;
            public List<SeSequence> Subtitle;
            public List<SeSequence> OriginalSubtitle;
            public List<SeUser> Users;
            public List<SeUpdate> Updates;

            public SeSession(string sessionKey, List<SeSequence> subtitle, string fileName, List<SeSequence> originalsubtitle)
            {
                Started = DateTime.Now;
                Id = sessionKey;
                FileName = fileName;
                Subtitle = subtitle;
                OriginalSubtitle = originalsubtitle;
                Renumber();
                Users = new List<SeUser>();
                Updates = new List<SeUpdate>();
            }

            public void Renumber()
            {
                for (int i = 0; i < Subtitle.Count; i++)
                    Subtitle[0].Index = i;
            }
        }

        private static SeSession GetFromCache(string key)
        {
            Cache cache = System.Web.HttpContext.Current.Cache;
            if (cache[key] != null)
                return (SeSession)cache[key];
            return null;
        }

        [WebMethod]
        public SeUser Start(string sessionKey, string userName, List<SeSequence> subtitle, List<SeSequence> originalSubtitle, string fileName, out string message)
        {
            SeSession session = GetFromCache(sessionKey);
            if (session != null)
            {
                RemoveInactiveUsers(session);
                if (session.Users.Count == 0)
                {
                    System.Web.HttpContext.Current.Cache.Remove(session.Id);
                }
                else
                {
                    message = "Session is already running";
                    return new SeUser();
                }
            }
            message = "OK";

            session = new SeSession(sessionKey, subtitle, fileName, originalSubtitle);
            SeUser user = new SeUser(userName, Context.Request.UserHostAddress);
            session.Users.Add(user);

            System.Web.HttpContext.Current.Cache.Add(session.Id, session, null, Cache.NoAbsoluteExpiration, new TimeSpan(0, 0, 5, 0), CacheItemPriority.AboveNormal, null); 
            return user;
        }

        private void RemoveInactiveUsers(SeSession session)
        {
            for (int i = session.Users.Count - 1; i >= 0; i--)
            {
                SeUser user = session.Users[i];
                if (user.LastActivity < DateTime.Now.AddMinutes(-MinuteTimeOut))
                {
                    session.Updates.Add(new SeUpdate(user, 0, 0, 0, string.Empty, "BYE"));
                    session.Users.RemoveAt(i);
                }
            }
        }

        [WebMethod]
        public List<SeUser> Join(string sessionId, string userName, out string message)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
            {
                message = "Session not found!";
                return null;
            }

            message = "OK";
            RemoveInactiveUsers(session);
            foreach (SeUser user in session.Users)
            {
                if (user.UserName == userName)
                {
                    if (user.Ip == Context.Request.UserHostAddress)
                        return session.Users;
                    message = "Username already in use!";
                    return null;
                }
            }
            RemoveInactiveUsers(session);
            SeUser newUser = new SeUser(userName, Context.Request.UserHostAddress);
            session.Users.Add(newUser);
            session.Updates.Add(new SeUpdate(newUser, 0, 0, 0, newUser.Ip, "USR"));
            return session.Users;
        }

        [WebMethod]
        public void Leave(string sessionId, string userName)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return;

            foreach (SeUser user in session.Users)
            {
                if (user.UserName == userName && user.Ip == Context.Request.UserHostAddress)
                {
                    user.LastActivity = DateTime.Now.AddDays(-1); // will be removed by "RemoveInactiveUsers"
                    break;
                }
            }
            RemoveInactiveUsers(session);

            if (session.Users.Count == 0)
                System.Web.HttpContext.Current.Cache.Remove(session.Id);
        }

        [WebMethod]
        public bool DeleteLines(string sessionId, List<int> indices, SeUser user)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return false;

            foreach (int index in indices)
            {
                if (index < 0 || index >= session.Subtitle.Count)
                    return false;
            }

            indices.Sort();
            indices.Reverse();
            foreach (int index in indices)
            {
                if (index >= 0 && index < session.Subtitle.Count)
                {
                    session.Subtitle.RemoveAt(index);
                    session.Updates.Add(new SeUpdate(user, index, 0, 0, string.Empty, "DEL"));
                }
            }
            return true;
        }

        [WebMethod]
        public bool InsertLine(string sessionId, int index, int startMilliseconds, int endMilliseconds, string text, SeUser user)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return false;

            if (index < 0 || index > session.Subtitle.Count)
                return false;

            SeSequence sequence = new SeSequence(index, startMilliseconds, endMilliseconds, text);
            session.Subtitle.Insert(index, sequence);
            session.Updates.Add(new SeUpdate(user, index, sequence.StartMilliseconds, sequence.EndMilliseconds, sequence.Text, "INS"));
            return true;
        }

        [WebMethod]
        public bool UpdateLine(string sessionId, int index, SeSequence sequence, SeUser user)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return false;

            if (index < 0 || index >= session.Subtitle.Count)
                return false;

            session.Subtitle[index] = sequence;
            session.Updates.Add(new SeUpdate(user, index, sequence.StartMilliseconds, sequence.EndMilliseconds, sequence.Text, "UPD"));
            return true;
        }

        [WebMethod]
        public bool SendMessage(string sessionId, string text, SeUser user)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return false;

            session.Updates.Add(new SeUpdate(user, 0, 0, 0, text, "MSG"));
            return true;
        }

        [WebMethod]
        public List<SeUpdate> GetUpdates(string sessionId, string userName, DateTime lastUpdateTime, out string message, out DateTime newUpdateTime, out int numberOfLines)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
            {
                newUpdateTime = DateTime.Now;
                message = "Session not found!";
                numberOfLines = 0;
                return new List<SeUpdate>();
            }

            bool userFound = false;
            foreach (SeUser user in session.Users)
            {
                if (user.UserName == userName)
                {
                    user.LastActivity = DateTime.Now;
                    userFound = true;
                    break;
                }
            }
            if (!userFound)
            {
                newUpdateTime = DateTime.Now;
                message = "User not found!";
                numberOfLines = 0;
                return new List<SeUpdate>();
            }

            newUpdateTime = DateTime.Now;
            numberOfLines = session.Subtitle.Count;
            List<SeUpdate> newUpdates = new List<SeUpdate>();
            for (int i=session.Updates.Count -1; i>=0; i--)
            {
                SeUpdate update = session.Updates[i];
                if (update.Time.Ticks >= lastUpdateTime.Ticks)
                    newUpdates.Add(update);
                else if (update.Time < DateTime.Now.AddMinutes(-MinuteTimeOut))
                    session.Updates.RemoveAt(i);
            }

            message = "OK";
            newUpdates.Reverse();
            return newUpdates;
        }

        [WebMethod]
        public List<SeSequence> GetSubtitle(string sessionId, out string fileName, out DateTime updateTime)
        {
            fileName = string.Empty;
            updateTime = DateTime.Now;
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return null;

            fileName = session.FileName;
            return session.Subtitle;
        }

        [WebMethod]
        public List<SeSequence> GetOriginalSubtitle(string sessionId)
        {
            SeSession session = GetFromCache(sessionId);
            if (session == null)
                return null;

            return session.OriginalSubtitle;
        }

    }
}


