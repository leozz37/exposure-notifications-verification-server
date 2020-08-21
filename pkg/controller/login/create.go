// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package login

import (
	"net/http"

	"github.com/google/exposure-notifications-verification-server/pkg/api"
	"github.com/google/exposure-notifications-verification-server/pkg/controller"
	"github.com/google/exposure-notifications-verification-server/pkg/controller/middleware"
)

func (c *Controller) HandleCreate() http.Handler {
	type FormData struct {
		IDToken string `form:"idToken,required"`
	}

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		session := controller.SessionFromContext(ctx)
		if session == nil {
			controller.MissingSession(w, r, c.h)
			return
		}
		flash := controller.Flash(session)

		// Parse and decode form.
		var form FormData
		if err := controller.BindForm(w, r, &form); err != nil {
			flash.Error("Failed to process form: %v", err)
			c.h.RenderJSON(w, http.StatusBadRequest, api.Error(err))
			return
		}

		// Get the session cookie from firebase.
		ttl := c.config.SessionDuration
		cookie, err := c.client.SessionCookie(ctx, form.IDToken, ttl)
		if err != nil {
			flash.Error("Failed to create session: %v", err)
			c.h.RenderJSON(w, http.StatusUnauthorized, api.Error(err))
			return
		}

		// Don't store the cookie if there is no database.User for it.
		user := middleware.VerifyCookieAndUser(ctx, c.client, c.db, session, cookie)
		if user == nil {
			controller.Unauthorized(w, r, c.h)
			return
		}

		// Set the firebase cookie value in our session.
		controller.StoreSessionFirebaseCookie(session, cookie)

		c.h.RenderJSON(w, http.StatusOK, nil)
	})
}