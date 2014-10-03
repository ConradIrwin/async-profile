AsyncProfile = require '../src'
assert = require 'assert'
describe 'AsyncProfile', ->

  it 'should call the callback', (done) ->

    new AsyncProfile(
      callback: (result) ->
        done()
    )
    process.nextTick ->

  it 'should wait for all ticks', (done) ->
    new AsyncProfile(
      callback: (result) ->
        assert.equal result.ticks.length, 4
        done()
    )

    process.nextTick ->
      process.nextTick ->
      process.nextTick ->
      process.nextTick ->

  it 'should work with the helper', (done) ->
    AsyncProfile.profile((->), callback: (result) ->
      assert.equal result.ticks.length, 1

      assert.deepEqual result.start, result.ticks[0].queue
      assert.deepEqual result.end, result.ticks[0].end
      done()
    )
