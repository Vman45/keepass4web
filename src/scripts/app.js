import jQuery from 'jquery'
import Css from '../style/app.css'
import React from 'react'
import ReactDOM from 'react-dom'

import Router from 'react-router/lib/Router'
import Route from 'react-router/lib/Route'
import useRouterHistory from 'react-router/lib/useRouterHistory'
import withRouter from 'react-router/lib/withRouter'

import { createHashHistory } from 'history'

import Viewport from './Viewport'

import UserLogin from './UserLogin'
import BackendLogin from './BackendLogin'
import DBLogin from './DBLogin'

const View        = withRouter(Viewport)
const UserForm    = withRouter(UserLogin)
const BackendForm = withRouter(BackendLogin)
const DBForm      = withRouter(DBLogin)

const appHistory = useRouterHistory(createHashHistory)()

// global namespace
window.KeePass4Web = {}

KeePass4Web.checkAuth = function(nextState, replace, callback) {
    return KeePass4Web.ajax('authenticated', {
        error: function(r, s, e) {
            var auth

            if (r.status == 401 && r.responseJSON)
                auth = r.responseJSON.message
            else
                KeePass4Web.error(r, s, e)

            if (!auth) return

            // route to proper login page if unauthenticated
            // in that order
            if (!auth.user) {
                KeePass4Web.clearStorage()
                replace({
                    pathname: '/user_login'
                })
            }
            else if (!auth.backend) {
                var template = KeePass4Web.getSettings().template
                if (template.type === 'redirect') {
                    window.location = template.url
                    // stopping javascript execution to prevent redirect loop
                    throw 'Redirecting'
                }
                else if (template.type === 'mask')
                    replace({
                        pathname: '/backend_login'
                    })
            }
            else if (!auth.db) {
                replace({
                    pathname: '/db_login'
                })
            }
        }.bind(this),
        complete: callback,
    })
}

// simple wrapper for ajax calls, in case implementation changes
KeePass4Web.ajax = function(url, conf) {
    conf.url  = url

    // set defaults
    conf.method   = typeof conf.method  === 'undefined' ? 'POST' : conf.method
    conf.dataType = typeof conf.dataType === 'undefined' ? 'json' : conf.dataType

    if (typeof conf.headers === 'undefined') {
        conf.headers = {}
    }
    conf.headers['X-CSRF-Token'] = KeePass4Web.getCSRFToken()

    KeePass4Web.restartTimer(true)
    return jQuery.ajax(conf)
}

KeePass4Web.logout = function(router) {
    KeePass4Web.ajax('logout', {
        // need async, else check for authenticated may finish first
        async: false,
        complete: function() {
            router.replace('/user_login')
        }
    })
    KeePass4Web.clearStorage()
}

KeePass4Web.closeDB = function(router) {
    KeePass4Web.ajax('close_db', {
        complete: function() {
            // redirect to home, so checks for proper login can be made

            // we haven't changed page, so need a workaround
            router.replace('/db_login')
            router.replace('/')
        },
    })
}

// leave room for implementation changes
KeePass4Web.clearStorage = function() {
    localStorage.removeItem('settings')
    localStorage.removeItem('CSRFToken')
}

KeePass4Web.setCSRFToken = function(CSRFToken) {
    localStorage.setItem('CSRFToken', CSRFToken || '')
}

KeePass4Web.getCSRFToken = function() {
    return localStorage.getItem('CSRFToken') || null
}

KeePass4Web.setSettings = function(settings) {
    var stored = KeePass4Web.getSettings()
    for (var k in settings) {
        stored[k] = settings[k]
    }
    localStorage.setItem('settings', JSON.stringify(stored))
}

KeePass4Web.getSettings = function() {
    var settings = localStorage.getItem('settings')
    if (settings)
        return JSON.parse(settings)
    return {}
}

KeePass4Web.timer = false
KeePass4Web.restartTimer = function(val) {
    if (typeof val !== 'undefined' ) KeePass4Web.timer = val
    return KeePass4Web.timer
}

KeePass4Web.error = function(r, s, e) {
    // ignore aborted requests
    if (e === 'abort')
        return
    if (r.status == 401) {
        if (this.props && this.props.router) {
            // redirect first, to hide sensitive data
            this.props.router.replace('/db_login')
            this.props.router.replace('/')
            alert('Your session expired')
        }
        else {
            alert('Your session expired')
            location.reload()
        }
    }
    else {
        let error = e
        if (r.responseJSON)
            error = r.responseJSON.message
        // disable remaining loading masks
        if (this.state) {
            this.setState({
                groupMask: false,
                nodeMask: false,
            })
        }
        alert(error)
    }
}


ReactDOM.render(
    <Router history={appHistory}>
        <Route path="/"              component={View} onEnter={KeePass4Web.checkAuth} />
        <Route path="/user_login"    component={UserForm} />
        <Route path="/backend_login" component={BackendForm} />
        <Route path="/db_login"      component={DBForm} />
    </Router>,
    document.getElementById('app-content')
)
