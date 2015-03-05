# Configures an external git repository
#
# Usage:
#  * Automatically reads, parses and updates a .gitexternals file if it only
#    contains lines in the form "# <directory> <giturl> <gittag>".
#    This function parses the file for this pattern and then calls
#    git_external on each found entry. Additionally it provides an
#    update target to bump the tag to the master revision by
#    recreating .gitexternals.
#  * Provides function
#    git_external(<directory> <giturl> <gittag> [NO_UPDATE, VERBOSE]
#      [RESET <files>])
#  git_external_manage(<file>)
#
# [optional] Flags which control behaviour
#  NO_UPDATE
#    When set, GitExternal will not change a repo that has already
#    been checked out. The purpose of this is to allow one to set a
#    default branch to be checked out, but stop GitExternal from
#    changing back to that branch if the user has checked out and is
#    working on another.
#  VERBOSE
#    When set, displays information about git commands that are executed
#
# CMake variables
#  GIT_EXTERNAL_USER_FORK If set, a remote called 'user' is set up for github
#    repositories, pointing to github.com/<user>/<project>. Defaults to user
#    name or GIT_EXTERNAL_USER environment variable.

find_package(Git)
if(NOT GIT_EXECUTABLE)
  return()
endif()

include(CMakeParseArguments)

set(GIT_EXTERNAL_USER $ENV{GIT_EXTERNAL_USER})
if(NOT GIT_EXTERNAL_USER)
  if(MSVC)
    set(GIT_EXTERNAL_USER $ENV{USERNAME})
  else()
    set(GIT_EXTERNAL_USER $ENV{USER})
  endif()
endif()
set(GIT_EXTERNAL_USER_FORK ${GIT_EXTERNAL_USER} CACHE STRING
  "Github user name used to setup remote for user forks")

macro(GIT_EXTERNAL_MESSAGE msg)
  if(${GIT_EXTERNAL_VERBOSE})
    message(STATUS "${NAME} : ${msg}")
  endif()
endmacro(GIT_EXTERNAL_MESSAGE)

function(GIT_EXTERNAL DIR REPO TAG)
  cmake_parse_arguments(GIT_EXTERNAL "NO_UPDATE;VERBOSE" "" "RESET" ${ARGN})
  get_filename_component(DIR  "${DIR}" ABSOLUTE)
  get_filename_component(NAME "${DIR}" NAME)
  get_filename_component(GIT_EXTERNAL_DIR "${DIR}/.." ABSOLUTE)

  if(NOT EXISTS "${DIR}")
    message(STATUS "git clone ${REPO} ${DIR}")
    execute_process(
      COMMAND "${GIT_EXECUTABLE}" clone "${REPO}" "${DIR}"
      RESULT_VARIABLE nok ERROR_VARIABLE error
      WORKING_DIRECTORY "${GIT_EXTERNAL_DIR}")
    if(nok)
      message(FATAL_ERROR "${DIR} git clone failed: ${error}\n")
    endif()
  endif()

  # set up "user" remote for github forks
  if(GIT_EXTERNAL_USER_FORK AND REPO MATCHES ".*github.com.*")
    string(REGEX REPLACE "(.*github.com[\\/:]).*(\\/.*)"
      "\\1${GIT_EXTERNAL_USER_FORK}\\2" GIT_EXTERNAL_USER_REPO ${REPO})
    execute_process(
      COMMAND "${GIT_EXECUTABLE}" remote add user ${GIT_EXTERNAL_USER_REPO}
      RESULT_VARIABLE nok ERROR_VARIABLE error
      WORKING_DIRECTORY "${DIR}")
  endif()

  if(IS_DIRECTORY "${DIR}/.git")
    if(${GIT_EXTERNAL_NO_UPDATE})
      GIT_EXTERNAL_MESSAGE("git update disabled by user")
    else()
      execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
        OUTPUT_VARIABLE currentref OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY ${DIR})
      GIT_EXTERNAL_MESSAGE(
        "current ref is \"${currentref}\" and tag is \"${TAG}\"")
      if(currentref STREQUAL TAG) # nothing to do
        return()
      endif()

      # reset generated files
      foreach(GIT_EXTERNAL_RESET_FILE ${GIT_EXTERNAL_RESET})
        GIT_EXTERNAL_MESSAGE("git reset -q ${GIT_EXTERNAL_RESET_FILE}")
        execute_process(
          COMMAND "${GIT_EXECUTABLE}" reset -q "${GIT_EXTERNAL_RESET_FILE}"
          RESULT_VARIABLE nok ERROR_VARIABLE error
          WORKING_DIRECTORY "${DIR}")
        GIT_EXTERNAL_MESSAGE("git checkout -q -- ${GIT_EXTERNAL_RESET_FILE}")
        execute_process(
          COMMAND "${GIT_EXECUTABLE}" checkout -q -- "${GIT_EXTERNAL_RESET_FILE}"
          RESULT_VARIABLE nok ERROR_VARIABLE error
          WORKING_DIRECTORY "${DIR}")
      endforeach()

      # fetch latest update
      execute_process(COMMAND "${GIT_EXECUTABLE}" fetch origin -q
        RESULT_VARIABLE nok ERROR_VARIABLE error
        WORKING_DIRECTORY "${DIR}")
      if(nok)
        message(STATUS "Update of ${DIR} failed:\n   ${error}")
      endif()

      # update tag
      GIT_EXTERNAL_MESSAGE("git rebase FETCH_HEAD")
      execute_process(COMMAND ${GIT_EXECUTABLE} rebase FETCH_HEAD
        RESULT_VARIABLE RESULT OUTPUT_VARIABLE OUTPUT ERROR_VARIABLE OUTPUT
        WORKING_DIRECTORY "${DIR}")
      if(RESULT)
        message(STATUS "git rebase failed, aborting ${DIR} merge")
        execute_process(COMMAND ${GIT_EXECUTABLE} rebase --abort
          WORKING_DIRECTORY "${DIR}")
      endif()

      # checkout requested tag
      execute_process(
        COMMAND "${GIT_EXECUTABLE}" checkout -q "${TAG}"
        RESULT_VARIABLE nok ERROR_VARIABLE error
        WORKING_DIRECTORY "${DIR}"
        )
      if(nok)
        message(STATUS "git checkout ${TAG} in ${DIR} failed: ${error}\n")
      endif()
    else()
      message(STATUS "Can't update git external ${DIR}: Not a git repository")
    endif()
  endif()
endfunction()

set(GIT_EXTERNALS ${GIT_EXTERNALS_FILE})
if(NOT GIT_EXTERNALS)
  set(GIT_EXTERNALS "${CMAKE_CURRENT_SOURCE_DIR}/.gitexternals")
endif()

if(EXISTS ${GIT_EXTERNALS} AND NOT GIT_EXTERNAL_SCRIPT_MODE)
  include(${GIT_EXTERNALS})
  file(READ ${GIT_EXTERNALS} GIT_EXTERNAL_FILE)
  string(REGEX REPLACE "\n" ";" GIT_EXTERNAL_FILE "${GIT_EXTERNAL_FILE}")
  foreach(LINE ${GIT_EXTERNAL_FILE})
    if(NOT LINE MATCHES "^#.*$")
      message(FATAL_ERROR "${GIT_EXTERNALS} contains non-comment line: ${LINE}")
    endif()
    string(REGEX REPLACE "^#[ ]*(.+[ ]+.+[ ]+.+)$" "\\1" DATA ${LINE})
    if(NOT LINE STREQUAL DATA)
      string(REGEX REPLACE "[ ]+" ";" DATA "${DATA}")
      list(LENGTH DATA DATA_LENGTH)
      if(DATA_LENGTH EQUAL 3)
        list(GET DATA 0 DIR)
        list(GET DATA 1 REPO)
        list(GET DATA 2 TAG)

        # Create a unique, flat name
        string(REPLACE "/" "_" GIT_EXTERNAL_NAME ${DIR}_${PROJECT_NAME})

        if(NOT TARGET update_git_external_${GIT_EXTERNAL_NAME}) # not done
          # pull in identified external
          git_external(${DIR} ${REPO} ${TAG})

          # Create update script and target to bump external spec
          if(NOT TARGET update)
            add_custom_target(update)
          endif()
          if(NOT TARGET update_git_external)
            add_custom_target(update_git_external)
            add_custom_target(flatten_git_external)
            add_dependencies(update update_git_external)
          endif()

          # Create a unique, flat name
          file(RELATIVE_PATH GIT_EXTERNALS_BASE ${CMAKE_SOURCE_DIR}
            ${GIT_EXTERNALS})
          string(REPLACE "/" "_" GIT_EXTERNAL_TARGET ${GIT_EXTERNALS_BASE})

          set(GIT_EXTERNAL_TARGET update_git_external_${GIT_EXTERNAL_TARGET})
          if(NOT TARGET ${GIT_EXTERNAL_TARGET})
            set(GIT_EXTERNAL_SCRIPT
              "${CMAKE_CURRENT_BINARY_DIR}/${GIT_EXTERNAL_TARGET}.cmake")
            file(WRITE "${GIT_EXTERNAL_SCRIPT}"
              "file(WRITE ${GIT_EXTERNALS} \"# -*- mode: cmake -*-\n\")\n")
            add_custom_target(${GIT_EXTERNAL_TARGET}
              COMMAND ${CMAKE_COMMAND} -DGIT_EXTERNAL_SCRIPT_MODE=1 -P ${GIT_EXTERNAL_SCRIPT}
              COMMENT "Recreate ${GIT_EXTERNALS_BASE}"
              WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
          endif()

          set(GIT_EXTERNAL_SCRIPT
            "${CMAKE_CURRENT_BINARY_DIR}/gitupdate${GIT_EXTERNAL_NAME}.cmake")
          file(WRITE "${GIT_EXTERNAL_SCRIPT}" "
include(${CMAKE_CURRENT_LIST_DIR}/GitExternal.cmake)
execute_process(COMMAND ${GIT_EXECUTABLE} fetch origin -q
  WORKING_DIRECTORY ${DIR})
execute_process(
  COMMAND ${GIT_EXECUTABLE} show-ref --hash=7 refs/remotes/origin/master
  OUTPUT_VARIABLE newref OUTPUT_STRIP_TRAILING_WHITESPACE
  WORKING_DIRECTORY ${DIR})
if(newref)
  file(APPEND ${GIT_EXTERNALS} \"# ${DIR} ${REPO} \${newref}\\n\")
  git_external(${DIR} ${REPO} \${newref})
else()
  file(APPEND ${GIT_EXTERNALS} \"# ${DIR} ${REPO} ${TAG}\n\")
endif()")
          add_custom_target(update_git_external_${GIT_EXTERNAL_NAME}
            COMMAND ${CMAKE_COMMAND} -DGIT_EXTERNAL_SCRIPT_MODE=1 -P ${GIT_EXTERNAL_SCRIPT}
            COMMENT "Update ${REPO} in ${GIT_EXTERNALS_BASE}"
            DEPENDS ${GIT_EXTERNAL_TARGET}
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}")
          add_dependencies(update_git_external
            update_git_external_${GIT_EXTERNAL_NAME})

          # Flattens a git external repository into its parent repo:
          # * Clean any changes from external
          # * Unlink external from git: Remove external/.git and .gitexternals
          # * Add external directory to parent
          # * Commit with flattened repo and tag info
          # - Depend on release branch checked out
          add_custom_target(flatten_git_external_${GIT_EXTERNAL_NAME}
            COMMAND ${GIT_EXECUTABLE} clean -dfx
            COMMAND ${CMAKE_COMMAND} -E remove_directory .git
            COMMAND ${CMAKE_COMMAND} -E remove -f ${CMAKE_CURRENT_SOURCE_DIR}/.gitexternals
            COMMAND ${GIT_EXECUTABLE} add -f .
            COMMAND ${GIT_EXECUTABLE} commit -m "Flatten ${REPO} into ${DIR} at ${TAG}" . ${CMAKE_CURRENT_SOURCE_DIR}/.gitexternals
            COMMENT "Flatten ${REPO} into ${DIR}"
            DEPENDS make_branch_${PROJECT_NAME}
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${DIR}")
          add_dependencies(flatten_git_external
            flatten_git_external_${GIT_EXTERNAL_NAME})
        endif()
      endif()
    endif()
  endforeach()
endif()
