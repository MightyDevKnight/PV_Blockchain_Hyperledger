/**
 * @class UserService
 * @classdesc
 * @ngInject
 */
function UserService($log, $rootScope, cfg, ApiService) {

  // jshint shadow: true
  var UserService = this;

  var user = cfg.users[0];

  UserService.setUser = function(u) {
    user = u;
  };

  UserService.getUser = function() {
    return user;
  };

  UserService.getUsers = function() {
    return cfg.users;
  };


  /**
   * @param {{username:string, orgName:string}} user
   */
  UserService.signUp = function(user) {
    return ApiService.signUp(user.username, user.orgName)
      .then(function(/** @type {TokenInfo} */data){
        $rootScope._token = data.token;
        return data;
      });
  };


}

angular.module('userService', []).service('UserService', UserService);